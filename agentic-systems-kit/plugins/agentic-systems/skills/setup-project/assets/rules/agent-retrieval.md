# Retrieval conventions

Applies whenever a knowledge base, search tool, vector store, chunking/embedding pipeline or retrieval step is created or changed. For the reasoning and provider settings, load the `rag-and-retrieval` skill.

- Choose the simplest strategy that passes the eval: whole corpus in a cached prompt (under ~200k tokens) → agentic search with grep/query tools → indexed RAG → fine-tuning only for behaviour problems, never for missing knowledge.
- Chunk by document structure first (headings, sections, tables), then size; prefix each chunk with its heading path and carry source, URL, date and access metadata on every chunk.
- Test contextual chunk enrichment (a short model-written context per chunk, prepended before embedding and keyword indexing).
- Default to hybrid search (embeddings + BM25/keyword) and over-retrieve then rerank; tune top-k on the eval set.
- Enforce access control in the retrieval layer, server-side, from the authenticated session. Never let the model supply the user, tenant or permission filter.
- Put retrieved documents before the question, instruct the model to answer only from them, allow "the documents don't say", and require citations that are verified in code or via a native citations feature.
- Evaluate retrieval (recall@k, MRR against gold chunks) separately from generation (faithfulness, correctness). Fix retrieval misses before touching the prompt.
- Golden sets include multi-chunk and unanswerable questions; generated questions are human-verified.
- Re-index on document change (re-contextualise all its chunks) and propagate deletions; retrieved content is untrusted data.
