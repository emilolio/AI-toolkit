---
name: chat-harness
description: Building the conversation layer of a chat product or assistant - the message store and what to replay to the model each turn, append-only history and thinking-block replay, the in-thread clearing/compaction ladder (tool-result clearing, server-side compaction, keep-recent-turns, when to start fresh), append-only replay that keeps the cache valid, streaming and interrupted turns, stop-reason handling, cross-conversation memory with user control, forking and branching, multi-tenant isolation and retention. Use when designing or debugging a chat UI backend, a persistent assistant thread, session resume, conversation summarisation or "memory" features, or when long chats get slow, expensive, truncated or forgetful. For what goes in the system prompt see context-engineering; for long-running autonomous work see agent-harness.
---

# Chat harness: history, compaction and memory for a conversation product

A chat API is stateless: every turn you send the whole conversation and get one assistant message back. The harness owns the message store and decides, on every request, what the model sees. Two constraints shape everything: the context window is finite and recall degrades as the context grows, before the window is full ("context rot"), and on current models the history you replay must be a content-identical extension of what produced earlier responses. So the design goal is an **append-only record** plus a **server-edited view**, with durable facts kept outside the thread.

## 1. Data model

Persist two things and keep them separate:

| Store | Contents | Rule |
|---|---|---|
| **Message record** | every API message exactly as sent or returned: role, the full `content` array (text, tool calls, tool results, thinking blocks with signatures, compaction blocks, fallback markers), request parameters that affect the prefix (model, system prompt version, tool set, thinking settings) | append-only; never edited, reordered or re-serialised |
| **Conversation state** | title, owner, workspace, pinned facts, memory references, the current compaction block, token estimate of the next request, last response id | mutable |

Store raw API content, not a rendered transcript; rebuild the request from it byte-for-byte. A serialiser that drops empty blocks or adds null fields breaks replay. Anything the user sees (markdown rendering, hidden tool chatter) is a view over the record, not the record.

## 2. The request you build each turn

```
tools (stable) → system prompt (stable) → [compaction block] → kept history → new user message
```

- **Alternate roles.** A tool-use loop is one assistant turn: assistant message with tool calls, user message with *only* tool results (one per call), next assistant message. User input that arrives mid-loop goes in a later user message.
- **Never mutate the prefix.** Changing the system prompt, tool definitions, or any earlier message invalidates the cache and, on current models, the signed thinking blocks that follow. Evolve instructions by appending (mid-conversation system messages, inline tool additions, per-message output config), not by editing.
- **Replay thinking blocks** unchanged and in order, including redacted ones. Filtering by block type and dropping the redacted variant breaks tool-use turns.
- **Keep per-session parameters pinned**: model, thinking mode and effort, tool choice, beta features. If you must switch model (for example after a refusal fallback), stay on the new model for the rest of the thread.
- **No per-request values in the static prefix** (timestamps, request ids, "today is …"). Put them in the newest user message or a mid-conversation system message.

## 3. Budget the window

Estimate the next request as `input + cache-read + cache-write + output` tokens of the last response, never from uncached input alone, and compare against a budget well under the window (the token-count endpoint previews it). Everything counts: system prompt, tool definitions, every message, images and documents, prior thinking on models that keep it, and the coming output.

Escalation order when the thread grows, cheapest first:

1. **Clear old tool results.** Lossless if the data can be re-fetched; free apart from a cache rewrite. Keep the last few, exclude memory and other must-keep tools, and only clear when enough tokens are freed to justify the cache miss.
2. **Compact server-side.** The API summarises the older range into a signed compaction block that replaces those messages. Keep the most recent turns verbatim so the conversation still feels continuous. Cut between an assistant reply and the next user message, never inside a tool loop.
3. **Start a fresh thread with durable state.** When the user's task can be rediscovered from files, memory or pinned facts, a clean window plus a short hand-off beats repeated compaction.

Compaction is lossy by design: high-level facts and decisions survive, obscure specifics do not; images, documents and fetched URLs in the summarised range are gone, and so are mid-conversation instructions. After compacting: restate standing instructions, re-attach files the user is still working on, and route verbatim-critical facts through memory or re-fetching rather than hoping the summary kept them. Tune the compaction instructions for recall first (nothing critical lost on hard real traces), then precision. Probe with evals: ask about an early fact after compaction and see what survives.

Client-side rolling summaries you write yourself cannot carry signed thinking blocks for the kept turns on current models; prefer the server-side mechanism.

## 4. Keep the cache warm across turns

- Enable automatic caching so the breakpoint moves forward each turn, and keep a breakpoint on the system prompt.
- Longer cache TTL for threads with idle gaps (a user who replies every twenty minutes).
- Tool-result-only turns keep the cache valid; a dropped or changed thinking block, a toggled tool, or an edited system prompt does not.
- In development, send the previous response id with each request and read the cache-miss diagnostic; `messages_changed` or `system_changed` means the harness is not append-only.

## 5. Streaming and interrupted turns

- Stream every response. Assemble blocks by index; a tool call's JSON arrives as fragments to parse once the block ends; a thinking block may arrive as only a signature and must still be stored.
- The final stop reason and cumulative usage come with the last delta event, not the first.
- If the stream drops: store the partial text as the assistant turn and add a user message asking the model to continue from where it stopped. Partial tool calls and thinking blocks are not recoverable; resume from the last complete text block. Do not prefill assistant turns on current models.
- Show partial output to the user as it streams, but write the record only from the assembled final message.

## 6. Branch on the stop reason

| Stop reason | Action |
|---|---|
| end of turn | done; an empty reply after a tool-result turn is not an error, at most append "please continue" |
| max output tokens | store the partial text, add a "continue from where you left off" user message; if the cut block is a tool call, retry with a higher limit |
| tool use | run the tools, reply with a tool-result-only user message, same tool set |
| paused turn (server-tool loop limit) | resend with the assistant content appended unchanged; cap continuations |
| context window exceeded | treat as truncated; clear or compact, then continue |
| compaction | on-demand: replace the summarised messages with the returned block and resend; threshold with pause: append the block and resend |
| stop sequence | the matched string is reported; treat as a normal end of turn |
| refusal | a success status, usually with empty content, sometimes mid-stream after partial output; do not store it as a turn in the record; retry on a different model with the credit mechanism (echo the partial output as one trailing assistant message only when the API says it has a prefill claim), then pin the thread to the fallback model; count refusals separately from errors |

Sum per-iteration usage for billing whenever compaction, server tools or fallbacks ran; the top-level counts omit them.

## 7. Cross-conversation memory

In-thread mechanisms (clearing, compaction) manage the live window; **memory** carries facts across threads. The memory store is yours: scope, retention and safety are product decisions.

- **Curated, not a transcript.** Progress notes, preferences, decisions, open items. Structured formats for state the model should not casually rewrite; free text for notes. Cap sizes; expire stale entries; warn the model before clearing so it can save essentials first (the API does this when memory and clearing are paired).
- **Scoped.** Per workspace or project, with account-level memory read-only inside a project and a switch to isolate fully; project memory dies with the project; never leak across tenants.
- **Visible and controllable.** One place where the user sees every remembered item and can edit or delete it; "remember X / forget Y" from inside the chat; per-chat off, pause (keep but stop using), reset (delete all); an incognito mode that writes neither history nor memory and is never searched later.
- **Category gates.** Sensitive categories (health, religion, politics, identity) opt-in only; a hard never-store list (government ids, account numbers, criminal or immigration history); strip sensitive data in the handler.
- **Surfaced deliberately.** A compact summary injected into context, or on-demand reads, plus an explicit, citable, user-toggleable "search past chats" tool; never silent injection of raw transcripts.
- **Lifecycle decoupled and disclosed.** Deleting a chat does not delete memories derived from it; retention windows apply to memory entries; memory is part of data export.
- **Hardened handler.** Paths confined to the memory root (reject traversal including URL-encoded), no delete or rename of the root, size caps, and memory read back into context treated as untrusted data.

See `references/memory-design.md` for a reference design.

## 8. Forking, branching and editing

Users expect to edit an earlier message or branch a thread. Because the record is append-only, implement both as **new threads that copy the prefix** up to the branch point; the original stays intact. A compaction block from the original can be reused only if the copied prefix is identical through that block. "Regenerate" is a fork at the last user message.

## 9. One in-flight turn per thread, and transport failures

- **Serialise requests per thread.** A double-send, or an edit while a turn is streaming, is the most common way a harness breaks append-only. Hold a per-thread lock; queue user input that arrives during a turn and send it as the next user message once the turn completes. Do not fan out parallel requests on a thread until the first response has started, or none of them will hit the cache.
- **Idempotent appends.** Give each outgoing request an idempotency key tied to the thread and the record position, so a retried request after a timeout cannot append the same turn twice.
- **Transport errors are not stop reasons.** Rate limits, overload (including an overload error event arriving mid-stream) and timeouts get exponential backoff with jitter and a retry cap; the partial stream is discarded unless it reached a clean block boundary. Surface a user-visible "retrying" state; after the cap, show the failure and keep the user's message so they can resend.
- **Uploaded files** referenced in a turn are dropped by compaction with the rest of the summarised range; keep file references in conversation state and re-attach the ones the user still needs.

## 10. Mid-turn user input and harness notices

Separate the user's words from harness-generated notices (clearing imminent, tool failed, budget low). User words go in a user message; notices go in a mid-conversation system message where the model supports it, otherwise in a clearly labelled block. Never put raw tool output in a system-role message; it would gain instruction authority.

## 11. Multi-tenant, retention, resume

- One store per tenant with the tenant id in every key; sessions resume only from a matching owner and workspace. Pass a stable per-user identifier in request metadata so abuse and usage can be attributed per tenant.
- Platform gaps: cache diagnostics and refusal-fallback headers are Claude-API-only; harnesses on Bedrock or Vertex need their own miss detection and fallback logic.
- Retention: delete the record, the compaction blocks, the cache diagnostics and the memory entries on their own schedules; tell users which deletes what.
- Hosted agent-SDK chats persist a session id per user and resume by it; mirror transcripts to durable storage for stateless hosts and dedupe by entry id.
- Isolate evals: a test thread must not share memory or cache with production threads.

## Anti-patterns

- Rendering history to text and re-sending it; trimming the middle; shortening old tool results client-side; re-encoding old images
- Timestamps or per-request data in the system prompt
- Stripping thinking blocks to save tokens, or losing redacted ones by filtering on type
- Hand-written rolling summaries on models with signed thinking
- Compacting inside a tool loop; sending two compaction blocks; sending the on-demand compaction request together with context-editing parameters (threshold compaction is itself a context edit and does combine with clearing)
- Storing a refusal as a turn; reading only top-level usage for billing
- Silent memory; one global memory pool across workspaces; storing sensitive categories by default
- Treating the SDK or the model as the conversation store

## Checklist

- [ ] Raw content arrays persisted; replay is byte-identical; append-only enforced in CI
- [ ] System prompt and tools frozen per thread; changes appended, not edited
- [ ] Token estimate per turn from full usage; budget below the window
- [ ] Clearing → compaction → fresh thread ladder implemented, with keep-recent-turns
- [ ] Post-compaction: instructions restated, files re-attached, probes in the eval suite
- [ ] Automatic caching plus system-prompt breakpoint; cache-miss diagnostics in dev
- [ ] Streaming assembly by index; interrupted-turn recovery
- [ ] Per-thread request lock, queued mid-turn input, idempotent appends, backoff on transport errors
- [ ] Every stop reason handled; refusals counted separately; usage summed across iterations
- [ ] Memory: scoped, visible, editable, category-gated, hardened handler
- [ ] Fork/branch/regenerate as prefix copies
- [ ] Tenant isolation and retention schedules documented

For Claude-specific parameters, headers and model caveats see `references/claude-conversation-mechanics.md`.

## Sources

- Context windows: https://platform.claude.com/docs/en/build-with-claude/context-windows
- Compaction: https://platform.claude.com/docs/en/build-with-claude/compaction
- Context editing: https://platform.claude.com/docs/en/build-with-claude/context-editing
- Prompt caching: https://platform.claude.com/docs/en/build-with-claude/prompt-caching
- Extended thinking (multi-turn): https://platform.claude.com/docs/en/build-with-claude/extended-thinking
- Streaming: https://platform.claude.com/docs/en/build-with-claude/streaming
- Handling stop reasons: https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons
- Memory tool: https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool
- Agent SDK sessions: https://code.claude.com/docs/en/agent-sdk/sessions
- Cookbook, context engineering (compaction, clearing, memory): https://platform.claude.com/cookbook/tool-use-context-engineering-context-engineering-tools
- Managing context on the Claude Developer Platform: https://claude.com/resources/articles/context-management
- Effective context engineering for AI agents: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Bringing memory to Claude: https://claude.com/resources/articles/memory
- Claude memory and chat search, user controls and data handling (support article): https://support.claude.com/en/articles/11817273
- Refusals and fallback: https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback
