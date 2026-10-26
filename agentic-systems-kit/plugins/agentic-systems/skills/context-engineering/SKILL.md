---
name: context-engineering
description: Managing everything that enters an agent's context window - writing system prompts at the right altitude, structuring instructions and examples, budgeting tokens across tools, prompts and history, prompt caching and cache-stable ordering, just-in-time retrieval and progressive disclosure, and long-horizon techniques (tool-result clearing, compaction, structured note-taking, memory, sub-agents, skills). Use when writing or revising a system prompt, assembling context for a model call, handling long conversations or tasks that exceed one context window, or when an agent loses track, repeats work or ignores instructions.
---

# Context engineering

Context engineering generalises prompt engineering. Instead of only crafting the instruction text, you curate the entire token state (system prompt, tool definitions, retrieved data, message history, memory) at **every step** of the agent loop. Because attention degrades as context grows ("context rot": n² attention cost, training skew toward shorter sequences, position-encoding interpolation), context is a finite resource with diminishing returns. The target at each step is **the smallest set of high-signal tokens that maximises the probability of the desired outcome**. Bigger context windows do not remove this constraint.

## 1. Anatomy of the context

| Component | Behaviour | Levers |
|---|---|---|
| Tool definitions | often the largest static block | fewer tools, deferred loading, concise descriptions (see `agent-tool-design`) |
| System prompt | stable | right altitude, sections, examples |
| Reference material | stable per task | load up front only if high-value and stable; otherwise retrieve |
| Memory / notes | small, persistent | structured notes outside the window |
| Message history | grows every turn | tool-result clearing, compaction, sub-agents |
| Tool results | spiky | concise formats, filtering in the tool, truncation with guidance |

Order static content first (tools → system prompt → reference docs → conversation) so caches hold.

## 2. System prompts

**Altitude.** Two failure modes: hard-coded if/else logic that is brittle and maintenance-heavy, and vague high-level guidance that assumes the model shares your context. Aim between: specific enough to give concrete signals, general enough to let the model use judgement. "Minimal" means no wasted tokens, not short.

**Process.** Start with a minimal prompt on the strongest model. Run real tasks. Observe failures. Add instructions and examples targeted at those failures. Remove anything that does not change behaviour.

**Structure.** Labelled sections with XML tags or Markdown headers: role/background, instructions, tool guidance, output format, examples. Keep it consistent.

**Content rules.**
- Be explicit about action vs suggestion ("Change this function", not "Can you suggest changes?"). Apply the colleague test: would a capable new colleague understand this?
- Explain the *why* behind rules; models generalise from motivation. Prefer "do X because Y" over bare prohibitions.
- Say what to do rather than only what not to do.
- Pick a default action posture explicitly: a block that says to proceed and implement, or a block that says to wait for instructions, depending on the agent.
- Encode safety boundaries in words the model can apply (reversible local actions are fine; destructive git or database operations need confirmation).
- Guide thinking generally ("think thoroughly about the trade-offs before choosing") rather than prescribing rigid step sequences; after tool results, ask it to reflect on quality before the next step.
- Tell the model that compaction exists so it does not wrap up early, and tell it how a fresh context window should re-orient (see `agent-harness`).
- Avoid pressure language ("CRITICAL", "you MUST always"); it causes over-triggering and strong models over-react to it.
- Avoid forcing sequential execution ("pause between steps"); it suppresses parallel tool use.

For the craft of writing the prompt text itself (examples, output format, structured outputs, reasoning modes, agentic prompt blocks, debugging, model migration) see `prompt-engineering`.

**Examples.** A few diverse, canonical examples wrapped in consistent tags beat an exhaustive list of edge cases. With extended thinking, an example may show problem → method → answer to convey approach, but do not ask the model to write out its reasoning in the response (see `prompt-engineering` §5).

**Long documents.** Put documents at the top and the question/instructions at the end (measurably better on long inputs); ask the model to extract relevant quotes before answering.

## 3. Where instructions live

- Always-on, project-wide conventions → the project-root CLAUDE.md (re-injected after compaction) or rules files.
- Area-specific conventions → path-scoped rules (reloaded when matching files are touched).
- Procedures and reference material used only sometimes → skills (only name + description are always in context; the body loads on demand; bundled files load when a step needs them).
- Per-task instructions → the user turn.
- Durable rules must not live only in the first user message: compaction can drop them.

Skills are the general mechanism for **progressive disclosure** of knowledge. Keep a skill's entry file focused, link supporting files from it one level deep, split contexts that rarely co-occur into separate files, and give `name`/`description` the most care because they are the triggering surface. For how to author one (structure, scripts, triggering, testing, skill vs rule vs tool) see `references/packaging-knowledge-as-skills.md`.

## 4. Retrieval: just-in-time over pre-loading

- Keep lightweight references (paths, IDs, queries, links) in context; fetch content when a step needs it.
- Let the agent explore incrementally; metadata (file names, folder hierarchy, sizes, timestamps) is a relevance signal. `tests/test_utils.py` and `src/core/test_utils.py` mean different things.
- Use selective reads (head, tail, grep, targeted queries) to inspect large data without ingesting it.
- Agentic search over a structured store first; semantic/vector search when you need speed or query variety, accepting lower accuracy and transparency.
- For indexed retrieval over a large corpus (chunking, embeddings, hybrid search, reranking, citations, retrieval evals) see `rag-and-retrieval`.
- Hybrid: pre-load stable, high-value material (a project's CLAUDE.md), retrieve the rest at runtime. Hybrids suit slower-changing domains.
- Unguided exploration burns context on dead ends; give the agent a map (what exists, where, naming conventions) and heuristics for picking tools.

## 5. Long-horizon techniques

For a chat product (a user-facing thread with a message store, streaming, resume and memory features) the `chat-harness` skill covers the conversation layer in depth; this section gives the techniques.

Pick by task shape; combine when needed.

| Technique | What | Best for |
|---|---|---|
| **Tool-result clearing** | Remove old tool outputs once they are deep in history and no longer needed; lightest form of compaction | Any long loop with chatty tools |
| **Compaction** | Summarise history when approaching the limit; continue with the summary plus the most recently touched files/state | Long conversational back-and-forth, long agent loops |
| **Structured note-taking** | The agent writes progress, decisions, to-dos to persistent storage outside the window and reads them back after resets | Iterative work with milestones (coding, multi-hour tasks) |
| **Sub-agents** | A lead holds the plan; workers explore in clean windows and return 1–2k-token summaries | Research and analysis where parallel exploration pays off |
| **Skills** | Procedural knowledge loaded on demand | Recurring workflows |

**Compaction rules.** Preserve architectural decisions, unresolved bugs, implementation details, the plan; discard redundant tool output. Tune for recall first (lose nothing critical), then precision. Keep full history client-side when the platform edits context server-side. Pair with notes so the agent saves what it needs before results are cleared.

**Hand-offs.** When a context runs low, spawn a fresh context with a careful handoff (plan, progress, references to artifacts) rather than letting it degrade. Store essentials externally and retrieve rather than redo.

## 6. Prompt caching

- Put a cache breakpoint on the last block that is identical across requests. Never on a timestamp, request ID or the newest user turn.
- Split breakpoints by change frequency: tools, then system prompt, then reference material, then conversation.
- Keep tool definitions stable: changing them invalidates the whole cache. Switching model, effort level or speed mode mid-conversation also forfeits the cache; weigh that before routing turns of one conversation to different settings. Changing tool choice or adding images invalidates only the messages level; the tools and system levels survive.
- Deterministic serialisation (stable key order) for anything replayed.
- Longer TTLs for side agents or workflows that pause more than a few minutes.
- Fleets of agents share cache entries when per-machine dynamic content is kept out of the static prefix.

## 7. Diagnosing context problems

| Symptom | Likely cause | Fix |
|---|---|---|
| Ignores instructions late in a long task | context rot, instruction only in first user turn | move to CLAUDE.md/rules; compaction with recall tuning; restate at hand-off |
| Repeats work after a reset | state only in conversation | notes file, progress log, plan in storage |
| Wrong tool or parameter | bloated/overlapping tool set | prune, namespace, deferred loading |
| Slow and expensive | large tool results, no caching | concise formats, filtering in tools, cache-stable ordering |
| Wraps up early | does not know compaction exists | say so in the prompt |
| Over-triggers a behaviour | pressure language, "if in doubt use X" | neutral wording, examples of when not to |

For Claude-specific mechanics (cache_control, context editing, server-side compaction, memory tool, context-window limits, model-specific prompting notes) see `references/claude-context-mechanics.md`.

## Sources

- Effective context engineering for AI agents: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Equipping agents for the real world with Agent Skills: https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
- Prompt engineering overview: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/overview
- Prompting best practices: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- Prompt caching: https://platform.claude.com/docs/en/build-with-claude/prompt-caching
- Context editing: https://platform.claude.com/docs/en/build-with-claude/context-editing
