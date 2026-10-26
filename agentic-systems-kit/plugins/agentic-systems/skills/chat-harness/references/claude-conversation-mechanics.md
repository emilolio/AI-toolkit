# Claude API mechanics for a chat harness

Parameter names, headers and model caveats for implementing `SKILL.md` on the Claude API, as documented in late October 2026. Several items are model-version-specific and change often; verify against the linked docs before relying on them.

## History and replay

- The API is stateless; send the full conversation in `messages` each turn (limit 100,000 messages). Consecutive same-role messages are merged, not rejected; still alternate deliberately.
- Tool loop: assistant message with `tool_use` blocks → user message containing **only** `tool_result` blocks (one per `tool_use_id`) → next assistant message. A `text` block after the results ends the turn (400 with server tools). Missing results produce a "tool_use ids were found without tool_result blocks" error.
- **Store the full assistant `content` array**: `thinking` (even with empty text; the `signature` matters), `redacted_thinking`, `text`, `tool_use`, `server_tool_use` and server results, `mcp_tool_listing`, `fallback`, `compaction`. In Python use `model_dump(exclude_none=True)` or `to_dict()`; a plain dump adds `null` fields the API rejects on compaction blocks.
- **Prefix-bound thinking** (Fable 5.1, Opus 5.5, Sonnet 5.5, Haiku 5.5): each thinking block's signature is bound to top-level `system`, the `tools` array and every earlier message. Editing, reordering or deleting an earlier message, changing `system`, adding/removing/editing a tool, shortening an earlier `tool_result` or re-encoding an earlier image invalidates every later thinking block. Not part of the check: `effort`, `max_tokens`, `output_config`, `tool_choice`, `metadata`, `thinking.display`, `cache_control`.
  - Accounts created on or after 2026-08-31 get a 400 (`invalid_request_error`, "bound to a different conversation") by default. Older accounts opt in with beta `thinking-binding-controls-2026-08-01` and `thinking.block_binding.prefix_mismatch_behavior: "error" | "drop_block"`; `drop_block` drops the failing block and all later ones, succeeds, and lists drops in `input_transformations` (`reason: "prefix_binding_mismatch"`). Run CI with `"error"`; alert on drops in production.
- Model switching mid-thread: each model reads its own blocks plus a fixed set of others; unreadable blocks are dropped silently and stay in your history. Sonnet 5.5 and Haiku 5.5 blocks are account-bound.
- **Evolving instructions without editing the prefix:** mid-conversation `role: "system"` messages (Fable/Mythos 5.x, Opus 5.5/5/4.8, Sonnet 5.5, Haiku 5.5; not Sonnet 5), carrying operator authority from their position, later ones overriding earlier; placement rules apply (not first, directly after a user or tool-result turn, not between `tool_use` and `tool_result`). Sonnet 5.5 and Haiku 5.5 may ignore a system message placed after a tool result; put the user's words in a trailing `text` block of the tool-result message instead. Turn-scoped reminders: `clear_at: "next_user_message"` (beta `mid-conversation-system-clear-at-2026-08-21`); keep re-sending the message verbatim. Tools: `tool_addition`/`tool_removal` blocks (beta `inline-tools-2026-09-15`, declare the full set up front with `defer_loading: true` on optional ones). Output format: per-message `output_config` (beta `mid-conversation-output-config-2026-07-01`). Disable tools with `tool_choice: {"type": "none"}` rather than removing `tools`.
- Prefill (ending `messages` with an assistant message) is a 400 on Claude 4.6+ and Mythos Preview. `temperature`/`top_p`/`top_k` are 400 on 4.7+ and on all models from API version 2026-10-21.

## Context window

- 1M tokens, up to 128k output, on Fable/Mythos 5.x, Opus 4.6+, Sonnet 4.6+, Haiku 5.5, no beta header. 200k on older models. Haiku 5.5 charges more above 100k input.
- Total input = `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`; `input_tokens` alone is only the post-breakpoint remainder. Output including thinking counts against the window during generation.
- Thinking retention: kept across turns on Opus 4.5+, Sonnet 4.6+, Haiku 5.5, Fable, Mythos (then billed as input each turn); stripped automatically on older models when a non-tool-result user message arrives. Override with `clear_thinking_20251015`.
- Input too large → HTTP 400. Input + `max_tokens` over the window on 4.5+ → accepted; if generation hits the limit, `stop_reason: "model_context_window_exceeded"`.
- Context-awareness tags (`<budget:token_budget>`, `<system_warning>`) are injected only on Sonnet 5/4.6/4.5 and Haiku 4.5; newer models use task budgets.
- Estimate with `POST /v1/messages/count_tokens`; it accepts `context_management` and returns post-edit `input_tokens` plus `context_management.original_input_tokens`.

## Context editing (beta `context-management-2025-06-27`)

`context_management: {"edits": [...]}`, applied server-side; your stored history is untouched.

- `clear_tool_uses_20250919`: `trigger` (default `{"type":"input_tokens","value":100000}`), `keep` (default 3 tool uses, oldest cleared first), `clear_at_least` (skip the edit if it cannot free that many tokens; use it so a clear is worth the cache miss), `exclude_tools` (e.g. `["memory"]`), `clear_tool_inputs`. Cleared results become placeholder text.
- `clear_thinking_20251015`: `keep: {"type":"thinking_turns","value":N}` or `"all"`; list it first when combined.
- Response: `context_management.applied_edits` (on the final `message_delta` when streaming).
- Caching: clearing invalidates the prefix from the clear point. On prefix-bound models, server-side edits never invalidate thinking blocks (the check compares what you sent).
- With the memory tool present, Claude is warned before results are cleared. Cookbook settings that worked: trigger 30k, keep 4, `clear_at_least` 10k; raise `keep` (e.g. 6) when combining with compaction.
- SDK client-side `compaction_control` is deprecated (removed in Python 1.0); use server-side compaction.
- The on-demand top-level `compaction` parameter cannot be sent together with `context_management`; threshold `compact_20260112` is itself a `context_management` edit and combines with tool-result clearing (raise `keep` so they do not fight).

## Compaction

All forms are beta and run on Fable 5/5.1, Mythos 5/5.1/Preview, Opus 4.6–5.5, Sonnet 4.6/5/5.5, Haiku 5.5. The docs recommend on-demand compaction where available; summarisation uses the request's model.

**On-demand** (beta `compact-2026-09-04`), the chat-harness default:
- Send the history with top-level `compaction: {"type": "summarize"}`, same `system`/`tools`/thinking settings, `max_tokens` of a few thousand, optional `instructions` (≤16,384 chars; replaces the default prompt entirely, so include "do not call tools" and what to preserve).
- Response: one `{"type":"compaction","content":"...","signature":"..."}` block, `stop_reason: "compaction"`, usage in `usage.iterations`. Rejected if the last assistant turn has an unanswered tool call, or with `stop_sequences`, `output_config.format`, or forced `tool_choice`.
- Replay: the block first in `messages` (its own assistant message or first block of the first message), summarised messages removed, exactly one block, unmodified, header present on every later request. Errors: `compaction_block_misplaced`, `compaction_signature_invalid`, `compaction_content_mismatch`, `compaction_nothing_to_summarize`; 529 `compaction_unavailable` → retry.
- If `stop_reason` is not `compaction` (`max_tokens`, `model_context_window_exceeded`, `tool_use`, `refusal`, `end_turn`), continue uncompacted and retry later with the matching fix.
- **Keep recent turns:** send only the older messages (cut so no tool call is split; the first kept message must have a different role from the last summarised one and must not be a mid-conversation system message, otherwise the API merges it into the summarised range), then rebuild as `[block, *kept_turns, new_user]`. Kept-turn thinking stays valid only if every compaction ran on a preserved-thinking model, the kept messages directly follow the summarised ones unchanged, and `system`/non-deferred `tools` are unchanged. Hand-written keep-tail summaries always fail the check.
- **Background:** snapshot `sent = len(history)`, keep chatting append-only, on arrival replace `history[:sent]` with the block; no second compaction until the first lands.
- Compact again by sending `compaction` on a history that already starts with a block; afterwards send only the newest block.
- Lost in the summarised range: images, documents, uploaded files and `container_upload` blocks, fetched URLs, per-message effort levels, mid-conversation system messages (restate them after the next user turn; re-attach files the user still needs). `cache_control` on the block places a breakpoint after the summary.

**Threshold** (beta `compact-2026-01-12`, edit `compact_20260112` inside `context_management.edits`): `trigger` default 150k (min 50k), `pause_after_compaction` (true → response is only the block with `stop_reason: "compaction"`; append and resend), `instructions`. The block appears at the start of the assistant content followed by the normal reply; on replay the API ignores everything before it. Streaming: `content_block_start` (type `compaction`) → one `compaction_delta` → `content_block_stop`. On prefix-bound models thinking before the block is not carried forward; strip thinking from any re-inserted turns or use `drop_block`.

Billing: `usage.iterations` lists `compaction`, `message` and (after a fallback) `fallback_message` entries; top-level counts exclude the compaction cost.

## Prompt caching across turns

- Top-level `cache_control: {"type":"ephemeral"}` enables automatic caching (breakpoint on the last cacheable block, moves forward each turn, uses one of the 4 slots). Keep an explicit breakpoint on the system prompt.
- Order `tools → system → messages`; a change at one level invalidates everything after. Invalidators: tool definitions, `tool_choice`, image add/remove, thinking type, top-level `output_config.effort` (setting it to the model default does not), model change, web-search or citation toggles. An effort change delivered as a per-message mid-conversation system message does not invalidate.
- Lookback is 20 blocks per breakpoint (a run of `tool_use` or `tool_result` blocks counts as one); add a second breakpoint in fast-growing threads.
- Minimum cacheable length: 512 tokens (Fable, Mythos 5/5.1, Opus 5/5.5, Sonnet 5.5, Haiku 5.5); 2,048 on Mythos Preview and Opus 4.7; 1,024–4,096 on other 4.x models.
- TTL 5 minutes (refreshed on hit) or `"ttl": "1h"` for idle chats; a 1h breakpoint must precede 5m ones. Writes 1.25× (5m) / 2× (1h); reads 0.1× (0.025× Fable/Mythos 5.1, 0.05× Opus/Sonnet 5.5). Cache reads are not deducted from rate limits.
- Tool-result-only user turns keep the cache valid; on last-turn-only thinking models a new non-tool user message strips earlier thinking and invalidates later messages.
- A cache entry is usable only after the first response starts; serialise the first request before any fan-out. `max_tokens: 0` pre-warms (not with streaming, manual extended thinking `thinking.type: "enabled"`, structured output, forced tools or batches); send the same adaptive thinking and effort config as the real turns.
- Diagnostics: `diagnostics: {"previous_message_id": <prev id | null>}` on each turn; the response's `diagnostics.cache_miss_reason.type` ∈ `model_changed`, `system_changed`, `tools_changed`, `messages_changed`, `previous_message_not_found`, `unavailable`, with `cache_missed_input_tokens`. A `null` `diagnostics` object means no comparison ran or none diverged; `{"cache_miss_reason": null}` means the comparison was still running (inconclusive; check the next turn). `previous_message_not_found` is not evidence that the request changed. Claude API only; not available on Bedrock or Vertex.

## Memory tool

- `tools: [{"type": "memory_20250818", "name": "memory"}]`, Claude 4+ models, no beta header. Commands: `view` (`path`, `view_range`), `create` (`file_text`), `str_replace` (`old_str`, optional `new_str`; omitting it deletes `old_str`), `insert` (`insert_line`, `insert_text`), `delete` (recursive on directories), `rename` (`old_path`, `new_path`; never overwrites). You implement them and return `tool_result` (`is_error: true` on failure).
- The API injects a system instruction to view memory first, record progress and assume interruption. Add scope and tidiness guidance yourself.
- Handler security and product design: see `memory-design.md`.

## Streaming

- `stream: true`. Events: `message_start` (empty content, initial `usage`, `input_transformations`, `diagnostics`) → per block `content_block_start` / `content_block_delta`* / `content_block_stop` → `message_delta` (`stop_reason`, cumulative `usage`, `context_management.applied_edits`) → `message_stop`. `ping` and `error` events (e.g. `overloaded_error`) can appear anywhere; handle unknown types gracefully.
- Deltas: `text_delta`, `input_json_delta.partial_json` (concatenate per `index`, parse at `content_block_stop`; `tool_use` starts with `input: {}`), `thinking_delta`, `signature_delta` (arrives before stop; keep the block even without thinking text, the norm with `display: "omitted"`), `compaction_delta` (threshold compaction only; the whole summary in one delta), `citations_delta`. An on-demand compaction block arrives complete inside `content_block_start` with no deltas; an assembler that only watches for `compaction_delta` drops it. A `fallback` block is an empty start/stop pair.
- Dropped stream: store partial text as the assistant turn, add a user message "Your previous response was interrupted and ended with […]. Continue from where you left off." Partial `tool_use`/`thinking` blocks are unrecoverable.
- The SDK requires streaming for large `max_tokens`; `stream.get_final_message()` returns the non-streaming shape.

## Thinking settings

- `thinking: {"type":"adaptive"}` is recommended and default on 5.x-era models; `enabled` + `budget_tokens` is a 400 on them; `disabled` is a 400 on Fable 5/5.1, Mythos 5/5.1/Preview, Opus 5.5 and Sonnet 5.5 (on Sonnet 5.5 use `between_tools` to turn off up-front thinking); Haiku 5.5 and Opus 5 accept it only at effort `high` or below. `display`: `omitted` (default on 5.x; empty text, signature populated), `summarized`, `updates` (beta). Billing is always the full thinking tokens.
- Inside a tool-use turn, pass back every `thinking`/`redacted_thinking` block that accompanied the `tool_use`, unmodified and in order. Across turns, pass everything back. Do not toggle thinking mid-turn; change it between turns and expect a message-level cache miss.
- Forced `tool_choice` (`any`/`tool`) is rejected on Opus 5.5, Sonnet 5.5, Fable 5.1, Mythos 5.1.

## Stop reasons

- `end_turn`; `max_tokens` (continue with a user message, no prefill on 4.6+; incomplete `tool_use` → retry with a higher limit); `tool_use`; `pause_turn` (server-tool loop limit, default 10: resend with content appended unchanged and the same `tools`); `model_context_window_exceeded`; `compaction`; `stop_sequence`.
- `refusal`: HTTP 200, usually empty content, `stop_details: {type:"refusal", category, explanation, recommended_model}`. Retry on a different model: server-side `fallbacks: "default"` or a list (beta `server-side-fallback-2026-07-01`; not Haiku 5.5, not batches), or the SDK refusal-fallback middleware; for a manual retry send `fallback-credit-2026-07-01`, the refused body with only `model` changed and the top-level `fallback_credit_token` added, matching beta headers, within the five-minute window. If `stop_details.fallback_has_prefill_claim` is true (refusal mid-stream after partial output) append exactly one assistant message echoing the refused `content`; otherwise resend without appending anything. Do not strip thinking blocks for the retry. Afterwards keep the returned content including the `fallback` block, drop thinking and client `tool_use` blocks from before the final `fallback` block, and stay on the fallback model. `recommended_model` is present only when `fallbacks` was set; a `fallbacks` list holds up to three models. In `usage.iterations` the declining model appears as a `message` entry and the serving model as `fallback_message`; tokens from different models are never summed into one field.

## Agent SDK sessions

- Transcripts are JSONL under `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` (or `$CLAUDE_CONFIG_DIR`). Options: `resume: <id>`, `continue`, `forkSession`/`fork_session` with `resume` (new id, copied history), `resumeSessionAt: <message uuid>`, `sessionId`, `persistSession: false` (TS; Python uses `CLAUDE_CODE_SKIP_PROMPT_HISTORY` in `env`; cannot be combined with a session store).
- Capture the id from `ResultMessage.session_id` (present on every result). Result `subtype` ∈ `success`, `error_max_turns`, `error_max_budget_usd`, `error_during_execution`, `error_max_structured_output_retries`; `stop_reason` carries the last API stop reason.
- Compaction is automatic; it emits a system message with `subtype: "compact_boundary"` (see the SDK type reference for its metadata fields). A `PreCompact` hook lets you archive the full transcript; `/compact` as a prompt forces it; a "summary instructions" section in CLAUDE.md steers what is kept. Standing rules belong in CLAUDE.md because it is re-injected each request.
- Stateless hosts: a `sessionStore`/`session_store` adapter with `append(key, entries)` and `load(key)` (optional `listSessions`, `delete`, …); `SessionKey = {projectKey, sessionId, subpath?}`; dual-write is best-effort (a `mirror_error` system message after 3 failed attempts), so dedupe by `entry.uuid`. Reference S3/Redis/Postgres adapters and a conformance suite exist.

## Sources

- Working with messages: https://platform.claude.com/docs/en/build-with-claude/working-with-messages
- Context windows: https://platform.claude.com/docs/en/build-with-claude/context-windows
- Context editing: https://platform.claude.com/docs/en/build-with-claude/context-editing
- Compaction: https://platform.claude.com/docs/en/build-with-claude/compaction
- Prompt caching: https://platform.claude.com/docs/en/build-with-claude/prompt-caching
- Extended thinking: https://platform.claude.com/docs/en/build-with-claude/extended-thinking
- Streaming: https://platform.claude.com/docs/en/build-with-claude/streaming
- Handling stop reasons: https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons
- Memory tool: https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool
- Agent SDK sessions: https://code.claude.com/docs/en/agent-sdk/sessions
