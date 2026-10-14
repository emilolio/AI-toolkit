---
name: rag-and-retrieval
description: Designing how an LLM app or agent gets knowledge it was not trained on - choosing between putting the corpus in the prompt, agentic search, indexed RAG and fine-tuning; chunking, contextual chunk enrichment, embeddings, hybrid lexical + semantic search, reranking, top-k, metadata filters and per-user access control; grounding, citations and abstention; re-indexing; and evaluating retrieval separately from generation (recall@k, MRR, faithfulness). Use when building a knowledge base, search tool, vector store, "chat with your docs" feature or retrieval step, or when answers are hallucinated, stale, uncited or miss documents that exist.
---

# RAG and knowledge retrieval

Retrieval is context engineering for knowledge the model does not have: the goal is to put the few chunks that answer the question into the window, and nothing else. Most RAG failures are retrieval failures (the right chunk was never retrieved, or was buried in noise), so measure retrieval on its own before tuning the prompt. Treat every technique below as a hypothesis to test on your eval set; the numbers quoted are from the sources' datasets, not yours.

## 1. Pick the retrieval strategy

Walk this ladder top to bottom; stop at the first rung that passes your eval.

| Rung | Use when | Notes |
|---|---|---|
| **Structured lookup** | answers are facts with fields (limits, prices, dates, eligibility rules, inventory) | extract into a database and query it deterministically; use text retrieval only for explanations and exceptions |
| **Put it all in the prompt** | corpus under ~200k tokens (~500 pages) and fairly static | cache the corpus; no index to build or keep fresh (Anthropic's stated threshold). At high query volume, price the per-query cost of a large cached prompt against an index |
| **Agentic search** | files, code or records an agent can navigate with grep / glob / targeted queries / an API | Anthropic found it more accurate, transparent and maintainable than vector search for agents; no stale index; slower |
| **Indexed RAG** (hybrid + rerank) | large corpus, latency budget too tight for multi-step search, many paraphrased queries | the rest of this skill |
| **Fine-tuning** | the problem is *behaviour* (format, tone, reasoning style), not missing knowledge | additive with RAG; RAG on a behaviour task can hurt by adding noise |

OpenAI's diagnosis rule: missing, outdated or proprietary knowledge is an *in-context memory* problem → retrieval. Inconsistent format or reasoning is a *learned memory* problem → prompt or fine-tune. Diagnose each eval failure before choosing.

Combining rungs is normal: load a small stable core (a glossary, a project overview) up front and retrieve the rest. Agents can combine both: an indexed `search_*` tool plus `read_*` tools for drilling into the source, with subagents running parallel queries and returning only excerpts when most material will be irrelevant.

## 2. Ingestion

- **Parse to clean text with structure kept**: headings, list items, page numbers, source URL, last-modified date. Use layout-aware parsing for PDFs, OCR for scans, and spot-check the output; garbage in the index cannot be fixed later.
- **Tables**: keep each table whole in one chunk where it fits; otherwise split by rows and repeat the header row (and the table's caption/section) in every piece, serialised as Markdown or `column: value` lines. Tables of facts are often better extracted into the structured-lookup rung.
- **Chunk by structure first, then size.** Split on headings/sections; keep chunks to a few hundred tokens (Anthropic) up to ~800 with overlap (OpenAI's vector-store default is 800 tokens with 400 overlap). Prefix each chunk with its heading path.
- **Contextual enrichment.** Before embedding and before BM25 indexing, have a model write 50–100 tokens situating each chunk in its whole document ("this section is from ACME's Q2 2023 10-K; revenue figures for EMEA"). Chunks lose meaning when cut out of their document; this restores it. Cache the document while you contextualise its chunks so cost stays low. Prompt in `references/retrieval-mechanics.md`.
- **Metadata on every chunk**: source ID, title, URL, section, document type, tenant/ACL tags, and **validity**: `effective_from` / `effective_to`, version or edition, and authority/precedence (e.g. emergency order > specific rule > general rule). Metadata powers filters, citations, freshness, precedence and access control.
- **Contextualise long documents per section**: the published cost figures assume ~8k-token documents; for very long documents pass the enclosing section (plus title and table of contents) instead of the whole document.
- **Re-index on change, keep history.** Re-contextualise all of a document's chunks when it changes. Mark superseded versions with an end date rather than silently overwriting when users can ask about past dates; delete removed documents explicitly (deletion in managed stores can be eventually consistent). Ingest high-urgency sources (emergency notices, recalls) on their own faster schedule.

## 3. Retrieval

- **Hard filters first**: apply metadata filters that must hold (jurisdiction, product, tenant, effective at the query's date) before similarity ranking, so similar-but-wrong chunks never compete. This is where precision matters; within the filtered set, favour recall.
- **Hybrid search by default** (lexical + semantic): embeddings for meaning, BM25/keyword for exact terms (error codes, product names, IDs). Fuse with reciprocal rank fusion or weighted scores; the Anthropic cookbook weights 0.8 semantic / 0.2 lexical as a starting point.
- **Over-retrieve, then rerank.** Pull ~100–150 candidates, rerank to the top ~10–20. Reranking mainly fixes *order* (MRR), not coverage; a hosted cross-encoder reranker added ~100–200 ms in Anthropic's cookbook; LLM reranking is slower.
- **Top-k is a tuned parameter.** More chunks raise the chance the answer is present and also distract the model; Anthropic found 20 beat 5 or 10 in their setup. Measure.
- **Choose the embedding model on your data**: domain fit, latency, cost, dimension/storage. Set query vs document input types where the model supports them. Contextualisation helped every embedding model Anthropic tested.
- **Query understanding**: extract the slots the filters need (entity, place, date, quantity) and ask a clarifying question when a required one is missing rather than guessing. Query rewriting (expansion, sub-queries, HyDE) can help vague or multi-part questions; gains vary by corpus, so eval it.
- **Multi-hop**: let an agent issue several searches and refine; cap the number of searches.

## 4. Access control (never delegate to the model)

Filter by the authenticated user's permissions **in the retrieval layer, server-side**, from the session identity, never from a tool argument the model fills in. Tag chunks with tenant/ACL attributes at ingestion, or keep one index per tenant. Neither the reranker nor the LLM can enforce permissions: once a chunk is in context, assume it can be repeated. (This is kit guidance; the sources do not prescribe a pattern.)

## 5. Generation

- **Documents first, question last** in long prompts (up to ~30% better in Anthropic's tests). Wrap each chunk with its index, source and content in consistent tags.
- **Ground and allow abstention**: "Answer only from the documents. If they do not contain the answer, say so." Explicit permission to say "I don't know" sharply reduces fabrication.
- **Quote first for long inputs**: extract verbatim quotes relevant to the question, then answer from the quotes.
- **Cite.** Use a native citations feature where available (pointers are guaranteed valid and cited text is cheaper than generated quotes); otherwise require a source index per claim and verify it in code. Optional post-check: for each claim, find a supporting quote or retract it.
- **Conflicting or overlapping sources**: pass precedence and effective dates with each chunk, tell the model the precedence rule, and require it to say when sources conflict instead of picking one silently. Better still, resolve precedence in code before generation.
- **High-stakes answers** (legal, medical, financial, safety): return a structured verdict (yes / no / depends / unknown) with conditions, citation and an "as of" date; abstain on ambiguity; link to the authoritative source; route a sample to expert review.
- Retrieved content is untrusted data; follow `agent-security` for injection defence.

## 6. Evaluate retrieval and generation separately

| Stage | Metric | Notes |
|---|---|---|
| Retrieval | **recall@k** (did the gold passage make the top k; Anthropic's "failure rate" = 1 − recall@20) | the metric that matters most once hard filters have removed wrong-scope chunks |
| Retrieval | **MRR** | rank of the first relevant hit; if MRR is well below hit rate, add a reranker |
| Generation | **faithfulness / groundedness** | every claim supported by retrieved text (LLM judge, strict output parsing) |
| Generation | **answer correctness** vs a reference answer | LLM judge with an "unknown" option |
| End to end | correctness, citation accuracy, abstention on unanswerable questions | include questions the corpus cannot answer |

Build a golden set of question → gold source span(s) (document + page/section, not chunk IDs, so labels survive re-chunking and re-indexing) → reference answer, including multi-passage, date-boundary, conflicting-source and unanswerable questions. Grade structured answers (verdicts, numbers, dates) with exact match, not a judge. Stratify by segment (region, product, document type) and weight errors by severity; track confident-wrong answers separately. LLM-generated questions are a fast start but skew generic; have humans verify them. Re-run the suite after every re-index. When a run fails, ask first: was the right chunk retrieved? Fix retrieval before touching the prompt. General eval practice is in `agent-evals`.

## Anti-patterns

- Building a vector index for a corpus that fits in a cached prompt
- Vector-only search for content full of exact identifiers
- Fixed-size chunking that cuts tables and sections in half; chunks without source metadata
- Passing top-3 with no reranking and never measuring recall
- Permission filtering done by the model or by a model-supplied argument
- No "I don't know" path; uncited answers; tuning the prompt to fix a retrieval miss
- Index never refreshed; deleted documents still served

## Checklist

- [ ] Strategy chosen on the ladder (structured lookup considered); reason recorded
- [ ] Structure-aware chunking with heading path, tables kept whole, full metadata incl. validity dates and precedence; contextual enrichment tested
- [ ] Hard metadata filters (scope, effective date) applied before ranking
- [ ] Hybrid search + reranker; top-k tuned on the eval set
- [ ] ACL / tenant filtering enforced server-side from the session identity
- [ ] Documents-first prompt, grounding and abstention instruction, citations verified
- [ ] Golden set labelled by source span, with reference answers, date-boundary, conflict and unanswerable questions; recall@k and faithfulness tracked separately; exact-match grading for structured answers
- [ ] Re-indexing and deletion path defined and tested

See `references/retrieval-mechanics.md` for the contextualisation prompt, provider-specific settings (Claude citations and search-result blocks, OpenAI file search and vector stores, embedding model options) and the measured results behind the defaults above.

## Sources

- Introducing Contextual Retrieval: https://www.anthropic.com/news/contextual-retrieval
- Contextual embeddings cookbook: https://platform.claude.com/cookbook/capabilities-contextual-embeddings-guide
- RAG guide cookbook: https://platform.claude.com/cookbook/capabilities-retrieval-augmented-generation-guide
- Citations: https://platform.claude.com/docs/en/build-with-claude/citations
- Search result content blocks: https://platform.claude.com/docs/en/build-with-claude/search-results
- Reduce hallucinations: https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations
- Effective context engineering for AI agents: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- OpenAI, Optimizing LLM accuracy: https://developers.openai.com/api/docs/guides/optimizing-llm-accuracy
- OpenAI, Retrieval and vector stores: https://developers.openai.com/api/docs/guides/retrieval
- OpenAI, Embeddings: https://developers.openai.com/api/docs/guides/embeddings
