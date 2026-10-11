# Claude API tool-use mechanics

Platform-specific details for implementing the principles in SKILL.md on the Claude API. Verify exact field names and model support against the current docs before relying on them; these notes reflect the docs at the time of writing.

## Tool definition

```json
{
  "name": "calendar_find_free_slots",
  "description": "Finds free time slots across the given attendees' calendars ... Use this before calendar_create_event. Do not use for ...",
  "input_schema": {
    "type": "object",
    "properties": {
      "attendee_ids": {"type": "array", "items": {"type": "string"}},
      "window_start_iso8601": {"type": "string"},
      "window_end_iso8601": {"type": "string"},
      "duration_minutes": {"type": "integer"},
      "response_format": {"type": "string", "enum": ["concise", "detailed"]}
    },
    "required": ["attendee_ids", "window_start_iso8601", "window_end_iso8601", "duration_minutes"],
    "additionalProperties": false
  },
  "strict": true,
  "input_examples": [
    {"attendee_ids": ["u_1042", "u_77"], "window_start_iso8601": "2026-03-02T08:00:00Z",
     "window_end_iso8601": "2026-03-02T17:00:00Z", "duration_minutes": 30}
  ]
}
```

- `name` must match `^[a-zA-Z0-9_-]{1,128}$`.
- `input_examples` must validate against the schema (the API rejects the request otherwise). Budget ~20–50 tokens per simple example, 100–200 for complex ones.
- `strict: true` uses grammar-constrained decoding so `input` always validates and the tool name is always valid. Schemas follow the structured-outputs JSON Schema subset. Compiled grammars are cached (24h), so keep sensitive data out of schema text.
- Optional: `cache_control` on the last tool definition to cache the tools prefix; `defer_loading: true` for tool search; `allowed_callers` for programmatic calling.

## Handling tool calls

- A response with `stop_reason: "tool_use"` contains one or more `tool_use` blocks (`id`, `name`, `input`). Check `stop_reason` first: `max_tokens` can truncate a tool input.
- Reply with a `user` message whose content is `tool_result` blocks: `{type: "tool_result", tool_use_id, content, is_error}`. `content` is a string or a list of text/image/document/search_result blocks; omit it for an empty result.
- Ordering rules (400 otherwise): every `tool_result` immediately follows the assistant turn that issued it; in that user message all `tool_result` blocks come before any text block.
- **Parallel calls:** one turn may contain several `tool_use` blocks. Run read-only/independent calls concurrently, side-effecting ones sequentially, and return **all results in one user message**. Sending each result in its own message teaches the model to stop parallelising and violates ordering. For a skipped call (dependent on an earlier failure) still return a `tool_result` with `is_error: true` explaining why.
- To encourage parallelism add a short system block asking for independent calls to be batched; measure average tool calls per tool-using turn (>1.0 means it works).
- Keep JSON key order in replayed `tool_use` inputs stable; randomised serialisation breaks caching.
- `tool_choice`: `auto` (default), `any`, `tool` (force a named tool), `none`. `disable_parallel_tool_use: true` lives inside `tool_choice`. On the newest models `any`/`tool` may be rejected; use `auto` with strict tools or structured outputs. Changing `tool_choice` invalidates the messages cache level only; tool definitions and the system prompt stay cached (changing tool definitions invalidates everything).
- Untrusted content (web pages, emails, documents) goes inside `tool_result` blocks, never in `system` or plain user text. See `agent-security`.

## Tool search (deferred loading)

- Pass all definitions; set `defer_loading: true` on discoverable ones; keep the 3–5 most-used always loaded.
- Add a tool search tool (regex or BM25 variants are built in; custom embedding search is possible). For MCP, use a toolset config with `defer_loading` default true and per-tool overrides.
- Use when definitions exceed ~10k tokens, you have 10+ tools or several MCP servers, or selection accuracy is poor. Cost: one extra search step of latency.
- Prompt caching is preserved because the loaded prefix stays stable.

## Programmatic tool calling

- Add the code-execution tool and set `allowed_callers` on tools to expose them as functions the model can call from code. Each in-code call surfaces as a `tool_use` with a `caller` field; only stdout returns to the model.
- Opt in tools that are independent and idempotent. Document return formats precisely.
- Example: budget compliance over 2,000+ expense lines went from ~200KB in context to ~1KB; 20+ calls in one code block eliminate 19+ inference passes.

## Memory tool

- A client-side tool type that the API knows about; you implement `view`, `create`, `str_replace`, `insert`, `delete`, `rename` against a `/memories` virtual prefix, and the API injects guidance to check memory first.
- Handlers must canonicalise paths, require the prefix, reject `..` and URL-encoded traversal, cap file sizes, and refuse to delete or rename the root.

## Sources

- Implement tool use: https://platform.claude.com/docs/en/agents-and-tools/tool-use/implement-tool-use
- Advanced tool use: https://www.anthropic.com/engineering/advanced-tool-use
- Memory tool: https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool
