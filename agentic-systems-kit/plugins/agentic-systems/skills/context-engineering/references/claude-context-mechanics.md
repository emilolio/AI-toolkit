# Claude API context mechanics

Platform-specific details for the principles in SKILL.md. Verify against current docs; these notes reflect the docs at the time of writing and several items are model-version-specific.

## Prompt caching

- `cache_control: {type: "ephemeral", ttl?: "1h"}` on a content block (5-minute TTL is the default), or top-level automatic caching (breakpoint on the last cacheable block). Up to 4 explicit breakpoints.
- Prefix order is tools → system → messages; a change at one level invalidates it and everything after. The system looks back up to ~20 blocks from a breakpoint for earlier cache entries.
- Minimum cacheable length is 512 tokens on current models (1k–4k on 4.x models); pad if just short.
- Writes cost more than normal input (5m ≈1.25×, 1h ≈2×); reads cost a small fraction. Usage reports `cache_creation_input_tokens`, `cache_read_input_tokens` and uncached `input_tokens`.
- Pre-warm a cache with `max_tokens: 0`.
- Invalidators: changing tool definitions invalidates every level; changing `tool_choice` or images invalidates the messages level only; thinking-config and effort changes invalidate at the levels shown in the docs' table. Mid-run tool additions have a dedicated mechanism (inline tool additions beta) so the prefix stays intact.
- Place 5m entries after 1h entries, not before.

## Context editing (server-side, beta)

- `context_management: {edits: [...]}` on the request.
- `clear_tool_uses_*`: fields `trigger` (default ~100k input tokens), `keep` (default last 3 tool uses), `clear_at_least`, `exclude_tools`, `clear_tool_inputs`.
- `clear_thinking_*`: keep N thinking turns or all; list it first when combined.
- The response reports `context_management.applied_edits`; the token-count endpoint accepts the same config.
- Practices: set `clear_at_least` so each cache invalidation is worth it; protect must-keep tools with `exclude_tools`; set `keep` explicitly when targeting several model tiers; pair with the memory tool so the agent writes notes before results disappear; keep full history client-side (edits are server-only).

## Server-side compaction (beta)

- An edit of type `compact_*` with `trigger` (input-token threshold, default ~150k, minimum ~50k), optional `pause_after_compaction`, optional `instructions` (replaces, not supplements, the default summary prompt).
- When it fires, the assistant content starts with a `compaction` block; replay that block on later requests (everything before it is ignored). With pause enabled, `stop_reason` is `"compaction"`; append the block and resend.
- Put a cache breakpoint at the end of the system prompt and `cache_control` on the compaction block. On the newest models drop thinking blocks from earlier turns you re-insert after the block.
- Prefer compaction for long agent loops and research accumulation. Kit inference, not from the docs: be cautious where the task needs precise recall of early details. Usage adds per-iteration entries; sum them for billing.

## Memory tool

- Client-side tool; you implement file operations under a `/memories` prefix. The API injects guidance to consult memory first. Combine with context editing for long-running agents.

## Context windows and thinking

- Current models default to a 1M-token window with large output limits. Thinking tokens count against `max_tokens`; newer models preserve prior thinking blocks as input.
- Overflow: input too long returns 400; overflow during generation on recent models yields `stop_reason: "model_context_window_exceeded"`.
- Adaptive thinking is the recommended mode; an `effort` setting controls depth. Select content blocks by `type`, not position, because thinking blocks may precede text.
- On the newest models history must be append-only: pass thinking blocks back unchanged; editing earlier turns or rebuilding `system`/`tools` invalidates later thinking blocks.
- Prefilling the assistant turn is not supported on recent models; use structured outputs or system instructions for format control.

## Model-specific prompting notes (verify for your model)

- Strong recent models over-react to aggressive language; use neutral wording.
- Some models are verbose and self-verify by default; drop legacy "double-check your work" instructions when they cause redundancy.
- Some models write fewer progress updates and issue fewer parallel calls in long loops unless asked explicitly; request both when you want them.
- Long-running tasks: have the model set up tests, an init script and a progress file in the first context window, and be prescriptive about how a fresh window re-orients (`pwd`, read the progress file, run the integration test).

## Claude Code / Agent SDK memory layout

- CLAUDE.md load order: managed/enterprise → `~/.claude/CLAUDE.md` → `./CLAUDE.md` or `./.claude/CLAUDE.md` → `./CLAUDE.local.md`. Files in cwd and every parent load at launch; subdirectory files load on demand. `@path` imports (depth 4) are supported. Target under ~200 lines per file; move procedures to skills and area rules to `.claude/rules/`.
- `.claude/rules/*.md` load with the same priority as `.claude/CLAUDE.md`; `~/.claude/rules/` holds user-level rules. The only frontmatter field read is `paths:` (glob list); a path-scoped rule loads when the model reads/edits a matching file. Invalid YAML makes the rule unconditional.
- After compaction: the project-root CLAUDE.md is re-injected; path-scoped rules reload on demand when matching files are touched; each invoked skill keeps only its first ~5k tokens within a shared ~25k budget. So durable instructions belong in CLAUDE.md, not only in a skill body or the first user turn.
- Skills: `<name>/SKILL.md` plus optional supporting files; name + description always in context; body on invocation. Keep SKILL.md under ~500 lines. See `packaging-knowledge-as-skills.md` for authoring guidance.

## Sources

- Prompt caching: https://platform.claude.com/docs/en/build-with-claude/prompt-caching
- Context editing: https://platform.claude.com/docs/en/build-with-claude/context-editing
- Context windows: https://platform.claude.com/docs/en/build-with-claude/context-windows
- Claude Code memory: https://code.claude.com/docs/en/memory
- Skills: https://code.claude.com/docs/en/skills
