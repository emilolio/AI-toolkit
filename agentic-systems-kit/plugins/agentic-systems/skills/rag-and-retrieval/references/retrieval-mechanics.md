# Retrieval mechanics: prompts, provider settings, measured results

Provider-specific detail behind `rag-and-retrieval`. Checked against the docs in October 2026; model names, limits and prices change, so re-check the linked pages before relying on a number.

## Contextualisation prompt (Anthropic Contextual Retrieval)

Run once per chunk, with the whole document cached so each document is paid for roughly once:

```
<document>
{{WHOLE_DOCUMENT}}
</document>
Here is the chunk we want to situate within the whole document
<chunk>
{{CHUNK_CONTENT}}
</chunk>
Please give a short succinct context to situate this chunk within the overall document for the purposes of improving search retrieval of the chunk. Answer only with the succinct context and nothing else.
```

Prepend the output to the chunk before embedding **and** before BM25 indexing. Add domain hints (a glossary of terms defined elsewhere in the corpus) when they help. Watch the embedding model's input limit: contextualised chunks that get truncated lose the benefit. Process all chunks of one document back to back so the cache stays warm (default TTL is 5 minutes).

Cost reported by Anthropic: about $1.02 per million document tokens, one time (800-token chunks, 8k-token documents, 100-token contexts). The cookbook run read ~62% of input from cache and cost ~$2.85 instead of ~$9.20.

## Measured results

Contextual Retrieval article (failure rate = 1 − recall@20, averaged across datasets):

| Setup | Failure rate | Reduction |
|---|---|---|
| Embeddings baseline | 5.7% | |
| + contextual embeddings | 3.7% | 35% |
| + contextual BM25 | 2.9% | 49% |
| + reranking (150 → 20) | 1.9% | 67% |

Anthropic RAG cookbook, basic → summary indexing + Claude rerank: MRR 0.74 → 0.87, end-to-end accuracy 71% → 81%, precision and recall nearly unchanged (reranking fixes order, not coverage).

OpenAI accuracy guide counter-example: on a behavioural task, fine-tuned model alone scored 87 (BLEU), fine-tuned + RAG scored 83. Retrieval added noise.

## Hybrid fusion (cookbook defaults)

- 150 candidates from each retriever (embeddings, BM25 over content + context).
- Weighted reciprocal rank fusion, 0.8 semantic / 0.2 lexical.
- Rerank the fused list; ~100–200 ms and ~$0.002 per query in the cookbook setup.

## Claude (Anthropic API)

- **No first-party embedding model.** Anthropic's docs point to Voyage AI: general models (`voyage-4-large` / `voyage-4` / `voyage-4-lite` at time of writing), domain models (code, law, finance), multimodal, contextualised chunk embeddings (`voyage-context-*`), rerankers. Always set `input_type` to `query` or `document`. Matryoshka dimensions and int8/binary quantisation cut storage 4×/32×.
- **Citations**: pass documents as `document` content blocks with `citations: {enabled: true}`. Plain text and PDFs are split into sentences; use custom-content documents to control citation granularity (one block per chunk). Cited text does not count toward output tokens. Not combinable with structured outputs. Documents can carry `cache_control`.
- **Search result blocks**: return `search_result` blocks (`source`, `title`, `content[]`, `citations`) from your own search tool to get web-search-style citations for RAG. Use stable URLs and descriptive titles; split long content into several text blocks for finer citation boundaries; on no hits return a text block saying so rather than an error.
- **Document layout** for long prompts:

```xml
<documents>
  <document index="1">
    <source>handbook/returns.md</source>
    <document_content>…</document_content>
  </document>
</documents>
```

- **Web search / web fetch** server tools: `max_uses` caps searches per request; newer tool versions support dynamic filtering (the model writes code to filter results before they reach context); web fetch only fetches URLs already in the conversation (exfiltration guard) and supports `max_content_tokens`.

## OpenAI

- **File search** (Responses API) over **vector stores**: managed parsing, chunking, embedding and hybrid search. Defaults: 800-token chunks, 400 overlap (`max_chunk_size_tokens` 100–4096; overlap ≤ half). `max_num_results` defaults to 10 (max 50). `ranking_options` sets the ranker, a `score_threshold`, and hybrid weights (`embedding_weight` / `text_weight`). `rewrite_query: true` rewrites the query and returns it. Attribute filters (`eq`, `ne`, `gt`, `gte`, `lt`, `lte`, `in`, `nin`, `and`, `or`; 16 keys per file). Results are cited via `file_citation` annotations; raw chunks need `include: ["file_search_call.results"]`. File deletion is eventually consistent; `expires_after` removes idle stores.
- **Embeddings**: `text-embedding-3-small` (1536 dims) and `text-embedding-3-large` (3072 dims), 8,192 input tokens, `dimensions` parameter to shorten vectors (re-normalise if you truncate manually), cosine similarity.

## Sources

- https://www.anthropic.com/news/contextual-retrieval
- https://platform.claude.com/cookbook/capabilities-contextual-embeddings-guide
- https://platform.claude.com/cookbook/capabilities-retrieval-augmented-generation-guide
- https://platform.claude.com/docs/en/build-with-claude/embeddings
- https://platform.claude.com/docs/en/build-with-claude/citations
- https://platform.claude.com/docs/en/build-with-claude/search-results
- https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool
- https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-fetch-tool
- https://developers.openai.com/api/docs/guides/retrieval
- https://developers.openai.com/api/docs/guides/tools-file-search
- https://developers.openai.com/api/docs/guides/embeddings
- https://developers.openai.com/api/docs/guides/optimizing-llm-accuracy
