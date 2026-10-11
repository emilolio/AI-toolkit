# Context and prompt conventions

Applies whenever a system prompt, prompt template, context assembly step, memory/compaction mechanism or retrieval path is created or changed. For the reasoning and the full checklist, load the `context-engineering` skill.

- Treat context as an attention budget with diminishing returns. The goal at every step is the smallest set of high-signal tokens that maximises the chance of the desired outcome.
- System prompts are written at the right altitude: specific enough to give concrete signals, general enough to avoid brittle if/else rule stacks. Explain the why behind each rule; say what to do rather than only what not to do.
- Structure prompts into labelled sections (XML tags or Markdown headers): role/background, instructions, tool guidance, output format, examples.
- Prefer 3–5 diverse canonical examples over exhaustive edge-case lists.
- Start minimal, run real tasks, then add instructions and examples only for observed failures.
- Order context for cache stability: tool definitions → system prompt → reference material → conversation. Never put timestamps, request IDs or other per-request values in the static prefix.
- Prefer just-in-time retrieval over pre-loading: keep lightweight references (paths, IDs, queries) in context and fetch content when a step needs it.
- Long-horizon tasks use explicit context management: clear stale tool results, compact when approaching limits, write durable notes to external storage, and delegate exploration to subagents that return condensed summaries.
- Tune compaction for recall first (nothing critical is lost), then precision. Tell the model that compaction exists so it does not wrap up early.
- Durable instructions live in the project CLAUDE.md (re-injected after compaction) or rules, not only in the first user message or a skill body.
- Reference material that applies only sometimes goes in a skill or a path-scoped rule, not in the always-on prompt.
