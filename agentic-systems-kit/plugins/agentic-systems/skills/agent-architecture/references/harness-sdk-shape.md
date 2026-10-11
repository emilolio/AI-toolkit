# What a mature agent harness provides (Claude Agent SDK as the reference)

Use this when deciding what to build yourself versus take from a harness SDK, and when configuring the Claude Agent SDK. Mechanics below reflect the SDK docs at the time of writing; verify against the current docs before relying on exact parameter names.

## Components a harness supplies

| Component | What it does | Build-vs-buy note |
|---|---|---|
| Agent loop | prompt → model → tool calls executed → results fed back → repeat until text-only response | Trivial to write, tedious to get right (parallel calls, error results, ordering rules, retries, streaming) |
| Built-in tools | Read, Edit, Write, Glob, Grep, Bash, WebSearch, WebFetch, ToolSearch, Agent (subagents), Skill, AskUserQuestion, task list | These are the "give the agent a computer" primitives |
| Permissions | allow/deny lists, permission modes, per-call callbacks, rule syntax like `Bash(npm *)` | Deterministic policy should live here or in hooks, not in prompts |
| Hooks | PreToolUse / PostToolUse / UserPromptSubmit / Stop / SubagentStart / SubagentStop / PreCompact callbacks that run in your process and cost no context | Use for blocking, auditing, injecting context |
| Sessions | session IDs, resume, fork, session store for stateless hosts | Needed for any multi-turn product |
| Compaction | automatic summarisation when the window fills, steerable via CLAUDE.md "summary instructions" | Hard to do well yourself; recall-first tuning matters |
| Memory files | CLAUDE.md / rules / skills re-injected after compaction | Put durable instructions here, not in the first user message |
| Subagents | named agent definitions with their own prompt, tools, model, effort, max turns | Context isolation + parallelism |
| MCP | standardised tool servers with auth handled | Prefer over bespoke integrations for common services |
| Budgets | max turns, max cost, effort level | Always set in production |

## Configuration guidance (Claude Agent SDK)

- **System prompt:** omitted means a minimal tool-calling prompt with none of the harness's safety text. Use the `claude_code` preset with `append` for coding-style agents; write a full custom prompt for non-coding or differently-permissioned agents and include a sentence explaining system reminders. The prompt is snapshotted for a resumed session until compaction.
- **Setting sources:** by default user, project and local settings load (CLAUDE.md, `.claude/rules/*.md`, skills, hooks). For multi-tenant deployments isolate filesystems, disable filesystem settings sources and disable auto-memory.
- **Permission modes:** interactive apps use the default mode with a `canUseTool` callback; trusted dev machines may auto-accept edits; fully bypassing permissions is only for isolated containers or CI.
- **Budgets:** set `max_turns` and `max_budget_usd`; leave headroom because the cap is checked after a response arrives.
- **Subagents:** scope `tools` to the minimum; write precise descriptions or name the agent in the prompt; a non-fork subagent sees only its own prompt, CLAUDE.md and tool definitions, and only its final message returns. Cap spawn depth and concurrency.
- **Hooks for policy:** when an action must be blocked deterministically, use a PreToolUse hook that returns a deny decision with a reason, not a prompt instruction.
- **Result handling:** iterate the stream to its end (trailing system events can follow the result), read the result subtype (`success`, `error_max_turns`, `error_max_budget_usd`, `error_during_execution`, …), and capture `session_id` for resume.
- **Cache-friendly fleets:** move per-machine dynamic content out of the system prompt so many instances share one cache entry.

## Anti-patterns

- Relying on an omitted system prompt to get the harness's safety behaviour.
- Treating CLAUDE.md as enforced configuration rather than advisory instructions.
- Changing the appended prompt on a resumed session and expecting it to apply.
- In the TypeScript SDK, passing a custom `env` without spreading the parent process environment (it replaces rather than merges; the Python SDK merges).
- Breaking out of the message stream on the first result message.

## Sources

- Agent SDK overview: https://code.claude.com/docs/en/agent-sdk/overview
- Building agents with the Claude Agent SDK: https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk
