# Reference design: cross-conversation memory for a chat product

Transferable principles drawn from the Claude memory tool docs and the design of memory in Claude.ai. Adapt the names; keep the separations.

## Layers

| Layer | Lifetime | Written by | Read by |
|---|---|---|---|
| Thread record | the thread | harness | harness (replayed to the model) |
| Compaction block | the thread, after a compaction | API | harness (replayed first) |
| Pinned facts | the thread | user ("remember this for this chat") | injected into the system or a system message |
| Project memory | the project | model (memory tool) and user (settings page) | threads in that project |
| Account memory | the account | model and user | threads outside projects; read-only inside projects unless isolated |
| Past-chat search | until retention expiry | harness (index) | an explicit tool call with citations |

## Storage shape

```
memories/
  <tenant>/<user>/account/        account-level notes (preferences, role, recurring projects)
  <tenant>/<user>/projects/<id>/  project notes, progress logs, decisions
```

The model sees the memory tool's `/memories` prefix; the handler maps it to the right directory for the caller and refuses anything outside it. Keep structured state (checklists, progress with pass flags) in JSON and notes in Markdown. Cap file sizes and the number of files; expire files untouched for N days with a warning entry.

## Handler rules

1. Canonicalise the path; require the `/memories` prefix; reject `..`, `..\`, and URL-encoded traversal.
2. Never delete or rename the root.
3. Enforce per-file and per-view size limits; paginate views; return an error for views beyond the documented line limit.
4. Strip sensitive categories on write (regex plus a small classifier): government ids, account numbers, health, religion, politics, identity unless the user opted in.
5. Return actionable errors (`is_error: true`) with the valid form.
6. Memory content read back into the model's context is untrusted data; label it so, and never put it in a system-role message.

## What the model is told

The API injects a base instruction to check memory first and record progress. Add, in the system prompt:

- scope ("only record information relevant to <product purpose>")
- what not to record (the never-store list, and sensitive categories without opt-in)
- tidiness (one topic per file, update rather than duplicate, keep a short index)
- when to write (after decisions, before a clearing warning, at the end of a unit of work)

## User controls (minimum)

- Settings page listing every memory item with edit and delete
- In-chat: "remember X", "forget Y", "don't use memory for this chat" (locks before the first message)
- Pause (retain, stop reading and writing) and reset (delete everything, including project memory)
- Incognito thread: no history, no memory writes, never indexed for past-chat search
- Project switch: "use account memory in this project" on or off
- Export includes memory; deleting a thread does not delete derived memories, and the UI says so

## Evaluate it

- Probes: after a session that wrote memory, start a fresh thread and ask for the fact; expect it from memory, not from re-reading sources. In Anthropic's cookbook run, memory halved file reads (8 → 4) and cut peak context roughly in half (≈334k → ≈173k tokens) in the second session.
- Negative probes: facts in the never-store list must not appear in memory after a session that mentioned them.
- Isolation probes: a thread in project A must not surface project B's memory.

## Sources

- Memory tool: https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool
- Bringing memory to Claude: https://claude.com/resources/articles/memory
- How does Claude's memory work (support): https://support.claude.com/en/articles/11817273
- Cookbook, context engineering: https://platform.claude.com/cookbook/tool-use-context-engineering-context-engineering-tools
