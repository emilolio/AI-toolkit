---
name: agent-tool-design
description: Designing, describing, evaluating and refactoring tools for AI agents - tool and MCP server design, naming and namespacing, input schemas, descriptions, result formats, error messages, token efficiency, tool search and deferred loading, programmatic/code-based tool calling, tool use examples, and the prototype-evaluate-improve loop. Use when creating or changing a tool, a tool schema, an MCP server, a tool result format, or when an agent misuses or ignores its tools.
---

# Tool design for agents

A tool is a contract between deterministic software and a non-deterministic caller. The agent may call it, answer from memory instead, ask a question, hallucinate an argument, or pick the wrong tool. Tools therefore cannot be lifted from developer-facing APIs; they must be designed for the agent, and the design must be empirical: prototype → evaluate → analyse → improve → repeat.

Tool definitions sit in the model's context on every turn and are the most prominent thing it sees. They are prompt engineering.

## 1. Choose which tools to build

- **Few, distinct tools beat many overlapping ones.** Overlap pulls the agent toward inefficient strategies. If a human could not say which of two tools to pick, merge them or sharpen their boundaries.
- **Design around tasks, not endpoints.** Do not wrap every API endpoint one-to-one. Ask what the agent needs to accomplish and build the tool that gets it there.
- **Consolidate steps that always happen together.** `schedule_event` (finds availability and books) instead of `list_users` + `list_events` + `create_event`. `get_customer_context` (compiles the relevant data) instead of five getters.
- **Search over list.** `search_contacts` / `message_contact` rather than `list_contacts`; `search_logs` (matching lines plus surrounding context) rather than `read_logs`.
- **Context is scarce; compute and storage are cheap.** Do filtering, joining, aggregation and summarisation inside the tool so the agent does not sift raw dumps.
- **Related operations can share one tool with an `action` parameter** when that reduces near-duplicate definitions without making the schema confusing.

## 2. Name and namespace

- Share a service prefix across related tools (`github_*`, `calendar_*`) and keep one word order consistently within a project (e.g. always `<service>_<action>_<resource>`: `github_list_prs`, `calendar_find_slots`). Namespacing reduces wrong-tool and wrong-parameter errors and keeps definitions discoverable.
- Descriptive names matter doubly when tools are found by search: `search_customer_orders` beats `query_db_orders`.
- Prefix vs suffix placement of the namespace affects results differently per model; test the scheme on your evals.

## 3. Write the schema

- Unambiguous, typed parameter names: `user_id` not `user`; `start_time_iso8601` or a documented format; enums for fixed choices.
- Strict schemas: `additionalProperties: false`, explicit `required`. Where the platform supports strict mode, turn it on so malformed inputs are impossible rather than validated and bounced.
- Make mistakes hard to make (*poka-yoke*): require absolute paths, require explicit units, reject ambiguous shorthand.
- Do not ask the model for its reasoning as a parameter (the API may refuse to fill such a field); ask for an explanation of the choice if you need one.
- Keep schema text free of sensitive data; compiled grammars may be cached.

## 4. Write the description (the highest-leverage part)

Write it as if onboarding a new hire who has none of your context. 3–6 sentences covering:

1. What the tool does.
2. When to use it, and when NOT to use it (name the alternative tool).
3. What each parameter means, including query syntax, domain terminology and how resources relate.
4. What it returns and what it does not do.
5. Edge cases and input format requirements.

Small wording changes can produce large behaviour changes (one description fix stopped the model appending the current year to every web search; precise refinements to tool descriptions were a key part of reaching state-of-the-art SWE-bench Verified results). The sentence counts above are a kit heuristic; the source's rule is "write it as you would for a new hire". Keep descriptions and implementations consistent, and never use "CRITICAL: you MUST use this tool" style pressure; it causes over-triggering.

Add **tool use examples** (an `input_examples` array where supported) when correct usage is not obvious from the schema: date conventions, ID patterns, when to populate optional nested objects, how parameters correlate, how two similar tools differ (`create_ticket` vs `create_incident`). Use realistic values, never placeholders like `"string"`. Show minimal, partial and full variants, 1–5 per tool. Skip them for trivial tools or for constraints the schema already enforces.

## 5. Shape the result

- **High-signal, token-efficient.** Return names, titles, URLs and the identifiers the next call needs. Drop UUIDs, MIME types, pixel dimensions and metadata the agent cannot act on. Mapping opaque IDs to readable names or simple 0-indexed IDs improved retrieval precision and reduced hallucinated IDs.
- **Paginate, filter, range-select, truncate by default.** When truncating, tell the agent how to narrow the query and encourage many small targeted calls over one broad one.
- **Offer `response_format`** (`concise` | `detailed`) on tools with potentially large output; a concise variant used roughly a third of the tokens in one measurement.
- **Choose the structure empirically.** JSON, XML and Markdown each have strengths; test against your evals rather than assuming.
- **Stable identifiers** so the agent can chain calls (search a user → message that user).
- Keep tool definitions and output formats stable across requests; churn invalidates prompt caches.

## 6. Errors

- Specific and actionable: what failed, why, and an example of a valid call. Never opaque codes or raw tracebacks.
- Flag errors explicitly in the result (an `is_error` marker where the platform supports it) so the model and the harness can distinguish failure from data.
- Tell the model when a tool failed so it can adapt; models typically retry 2–3 times with corrected inputs when the error message is instructive.
- For a batch of parallel calls where one fails and the rest are skipped, still return a result for every call, marking the skipped ones as errors with the reason.

## 7. Annotate and guard

- Declare open-world access and destructive behaviour (MCP tool annotations; read-only hints let the harness run calls concurrently).
- Destructive or irreversible tools get a confirmation step in the harness, not just a warning in the description. See `agent-security`.
- Independent, idempotent tools are the ones to expose to programmatic/code-based calling.

## 8. Scale the tool set

When definitions grow past roughly 10k tokens, ten-plus tools, or multiple MCP servers:

- **Deferred loading / tool search.** Keep the 3–5 most-used tools always loaded; mark the rest discoverable by a search tool that returns full definitions on demand. This preserved cache prefixes and cut definition tokens by ~85% while improving selection accuracy in Anthropic's measurements. Add system-prompt guidance describing capability areas and telling the model to search.
- **Code execution over tool-call chains.** Expose tools as typed functions the model can call from code in a sandbox. Loops, conditionals, retries and polling become ordinary code; large intermediate results stay in the execution environment and only what is logged or returned reaches the model. One workflow dropped from ~150k to ~2k tokens. Use for large datasets where only aggregates matter, 3+ dependent calls, filtering/sorting before the model sees data, and parallel fan-out. Skip for single calls and small lookups. Document return formats precisely (field names, types, enums, timestamp formats) because the model writes parsing code from them. Requires a secure sandbox, resource limits and monitoring.
- **Progressive disclosure of MCP servers** as a filesystem: one typed function file per tool, discovered with directory listings; or a `search_tools` tool with a detail-level parameter (names only → names + descriptions → full schemas).

## 9. Prototype → evaluate → improve

1. **Prototype fast.** Give the model the docs for every library/API the tool depends on. Wrap tools in a local MCP server so you can test them live in an agent harness, or pass them directly into API calls.
2. **Use the tools yourself** and collect early user feedback to learn real prompts and use cases.
3. **Build an eval** from real-world use with realistic data sources: multi-step tasks with context and a goal (schedule a meeting with X, attach notes, book a room), not single-step lookups with an explicit ID. Pair each task with a verifiable outcome; keep verifiers tolerant of formatting differences. Optionally record expected tool sequences but do not overfit to one path. Keep a held-out set.
4. **Run it** with a simple loop per task; ask the agent for reasoning/feedback blocks before tool calls (or enable interleaved thinking) so you can see why a tool was or was not called.
5. **Measure** accuracy, per-task runtime, tool-call count, token consumption and tool errors. Redundant calls → adjust pagination or limits. Frequent invalid-parameter errors → description or examples are unclear.
6. **Read transcripts.** What the agent does not say matters as much as what it says.
7. **Let the agent refactor the tools.** Paste transcripts into a coding agent and ask it to find contradictory descriptions, confusing schemas and inefficient implementations. Tools refined this way beat expert-written tools on held-out sets.

## Anti-patterns

- Thin wrapper over every API endpoint
- Tools that return everything and leave the agent to filter
- Overlapping tools with fuzzy boundaries
- Low-level identifiers and metadata leaked into results
- Unbounded responses without pagination or truncation guidance
- Opaque errors, stack traces, `"failed"`
- One-line descriptions; descriptions that assume shared context
- Pressure language in descriptions ("ALWAYS", "CRITICAL")
- Loading hundreds of tool definitions up front
- Piping large intermediate payloads through the model
- Evaluating on single-step toy tasks or brittle exact-match verifiers
- Rebuilding the tool array per request (breaks caching)

## Checklist for a new or changed tool

- [ ] Solves a task the agent needs, not a raw endpoint
- [ ] No overlap with existing tools; namespaced name
- [ ] Strict schema, unambiguous typed parameters
- [ ] Description covers what / when / when not / parameters / returns
- [ ] Results are concise by default, paginated, with narrowing guidance on truncation
- [ ] Errors are actionable and flagged
- [ ] Destructive behaviour annotated and gated
- [ ] Input example added if usage is non-obvious
- [ ] At least one realistic multi-step eval task; transcripts reviewed

For building the MCP server that exposes these tools (primitives, transports, authorization, MCP-specific security, testing, distribution) see `mcp-server-development`.

For platform-specific mechanics (tool definition fields, result ordering rules, parallel calls, strict mode, deferred loading, programmatic calling) see `references/claude-tool-use-mechanics.md`.

## Sources

- Writing effective tools for agents - with agents: https://www.anthropic.com/engineering/writing-tools-for-agents
- Introducing advanced tool use: https://www.anthropic.com/engineering/advanced-tool-use
- Code execution with MCP: https://www.anthropic.com/engineering/code-execution-with-mcp
- Building effective agents (ACI section): https://www.anthropic.com/engineering/building-effective-agents
- Tool use docs: https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview
