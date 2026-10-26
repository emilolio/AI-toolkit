# Conversation conventions

Applies whenever the message store, request assembly, history trimming, compaction, caching across turns, streaming, session resume or memory features of a chat product change. For the reasoning and the Claude-specific mechanics, load the `chat-harness` skill.

- Persist every API message as its raw content array (including thinking, redacted thinking, compaction and fallback blocks) and replay it byte-for-byte. History is append-only; a rendered transcript is a view, never the source.
- The system prompt and tool set are frozen for the life of a thread. Evolve instructions by appending (mid-conversation system messages, inline tool additions, per-message output config), never by editing earlier content.
- No timestamps or per-request values in the static prefix; they go in the newest user message or a system message.
- Pin model, thinking settings, effort, tool choice and beta features per thread; after a refusal fallback, stay on the fallback model.
- Estimate the next request from full usage (input + cache read + cache write + output), never from uncached input alone, and act well before the window: clear old tool results → server-side compaction with recent turns kept → fresh thread with durable state.
- Compact only between an assistant reply and the next user message. Afterwards restate standing instructions and re-attach files the user still needs. Keep compaction probes in the eval suite.
- No hand-written rolling summaries on models with signed thinking blocks; use the server-side mechanism.
- Automatic caching on, with a breakpoint on the system prompt; cache-miss diagnostics enabled in development and alerted on for `messages_changed`, `system_changed` and `tools_changed`.
- One in-flight request per thread; queue mid-turn user input as the next user message; idempotency keys on appends; backoff with a retry cap on transport errors.
- Stream every response, assemble by block index, keep signature-only thinking blocks, take the stop reason from the final delta. Interrupted turns: store partial text, continue with a user message, never prefill.
- Handle every stop reason explicitly; a refusal is never stored as a turn in the record (echo partial output on the retry only when the API reports a prefill claim); sum per-iteration usage for billing.
- Memory is scoped per workspace, visible and editable by the user, category-gated, never silently injected; the handler confines paths to the memory root and treats memory content as untrusted data.
- Fork, branch, edit-earlier-message and regenerate are new threads that copy the prefix; the original is never mutated.
- Tenant id in every storage key; retention schedules for records, compaction blocks and memory documented and disclosed.
