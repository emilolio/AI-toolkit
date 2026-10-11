---
name: multi-agent-orchestration
description: Designing systems where a lead agent coordinates subagents - when multi-agent is worth its cost and when it is not, orchestrator-worker architecture, precise delegation, subagents as filters that return condensed findings, scaling effort to task complexity, parallelism, model selection per role, hand-offs between contexts, and evaluating multi-agent systems. Use when adding subagents, splitting work across agents, designing a research or orchestration system, or when subagents duplicate work, go off-scope or flood the lead with data.
---

# Multi-agent orchestration

The orchestrator-workers pattern: a lead agent analyses the task, plans, spawns workers that each own a clean context window, synthesises their condensed findings, and decides whether more work is needed. It is a way to **spend many more tokens productively** on a problem while keeping each context focused. It is also the most expensive pattern you can pick, so the first question is whether you need it.

## 1. When multi-agent fits (and when it does not)

**Good fit**
- Highly parallelisable work (breadth-first research, many independent lookups, many files to analyse)
- Information that exceeds one context window
- Many complex tools where specialisation reduces confusion
- Open-ended tasks where each finding changes the next step, so a fixed pipeline cannot be hardcoded

**Poor fit**
- Tasks that need shared context across every step
- Heavy inter-agent dependencies (most coding tasks)
- Few parallel subtasks
- Single-file edits or anything one agent handles in a few calls (over-delegation is a common failure)

**Economics.** On an internal research eval, token usage explained ~80% of performance variance; tokens + tool calls + model choice explained ~95%. A lead on the strongest model with workers on a mid-tier model beat a single strongest-model agent by ~90%. Agents use roughly 4× the tokens of chat; multi-agent roughly 15×. Only high-value tasks justify it. A newer model beat doubling the token budget on an older one, so upgrade models before scaling agent count.

## 2. Architecture

```
user → lead agent (plan; save plan to storage) ──spawns──▶ worker 1 (clean context, own tools)
                      ▲                                   ▶ worker 2
                      │  condensed findings + refs        ▶ worker N
                      └── synthesise → more workers? → final answer → (optional) citation / verification agent
```

- The lead holds the plan and the synthesis; it does not do the exploration itself.
- Save the plan to external storage before spawning so it survives context truncation.
- Separate concerns into separate agents when they have different quality criteria (e.g. a dedicated agent that attributes claims to sources after the research is done).

## 3. Subagents are filters, not relays

Each worker runs iterative searches or analysis in its own window (often tens of thousands of tokens) and returns only the important findings, condensed to roughly 1–2k tokens, plus references to any artifacts it wrote (files, reports, data). The lead never receives raw dumps. This is the whole point: compression of information per unit of lead context.

Reduce "telephone" loss by having workers write substantial outputs (code, reports, tables) to storage and pass lightweight references rather than re-describing them through the lead.

## 4. Delegate with precision

Vague delegation ("research the semiconductor shortage") produced one worker studying a 2021 crisis while two others duplicated current supply-chain work. Every delegation states:

1. **Objective** - the question or artifact
2. **Output format** - exact shape and length
3. **Tools and sources** - which to use, where the data actually lives (searching the web for something that only exists in an internal system is a classic miss)
4. **Boundaries** - what is out of scope, what other workers cover
5. **Effort budget** - max tool calls / tokens / time
6. **Return contract** - condensed findings plus references, not raw data

Small changes to the lead's prompt shift worker behaviour unpredictably; the lead's prompt must define the collaboration framework (division of labour, effort budgets, how to resolve overlap), not just the task.

## 5. Scale effort to complexity with explicit rules

Give the lead heuristics, because models under-estimate the needed depth or over-spawn:

| Task class | Workers | Tool calls per worker |
|---|---|---|
| Simple fact-finding | 1 | 3–10 |
| Direct comparison | 2–4 | 10–15 each |
| Complex multi-part research | 10+ with divided responsibilities | as needed, with caps |

Add guardrails against runaway behaviour: cap concurrent workers, cap spawn depth, cap total budget, stop endless searching for sources that do not exist.

## 6. Search and tool heuristics for workers

- **Start wide, then narrow.** Short broad queries first, evaluate what exists, then progressively specific ones. Over-long, over-specific queries return nothing.
- **Survey the tools first,** match tool to intent, prefer specialised tools over generic ones, use web search for broad exploration only.
- **Judge source quality** explicitly (authoritative over SEO content farms); humans caught this failure when automated evals did not.
- **Adapt to findings**: the plan is a hypothesis, not a script.
- **Use thinking as a scratchpad**: the lead plans tools, complexity and worker roles; workers reflect after each tool result to assess quality and gaps.

## 7. Parallelise at two levels

- The lead spawns several workers at once (3–5 is a good default).
- Each worker issues several independent tool calls in parallel.
Parallelism cut research time by up to ~90% on complex queries in Anthropic's system.

Current limitation: synchronous batches block steering and inter-worker communication until all return. Asynchronous orchestration helps but complicates state consistency and error propagation; design for it only when you can handle both.

## 8. Context hand-offs

When a lead or worker approaches its limit: summarise completed phases, store essentials externally, spawn a fresh context with a careful hand-off (plan, progress, artifact references), and retrieve stored plans rather than redoing work. The session-level version of this (orientation and hand-off routines, state files) is in the `agent-harness` skill.

## 9. Model and effort selection per role

- Lead: strongest model, higher effort; it plans and synthesises.
- Workers: in Anthropic's research system a mid-tier model was sufficient for workers and far cheaper; use lower effort for lookup-style work.
- Judges / classifiers: smallest model that passes calibration.
Measure in your own system; do not assume the split transfers.

## 10. Evaluating multi-agent systems

- Evaluate outcomes, not paths: agents take different valid routes to the same answer.
- Start with ~20 representative queries; early changes have huge effects (a prompt tweak can move success from 30% to 80%).
- One LLM-judge call with a single rubric (factual accuracy, citation accuracy, completeness, source quality, tool efficiency) scoring 0–1 with pass/fail worked best; pair with human testers who catch what judges miss.
- For stateful tasks, evaluate final environment state; for complex workflows define checkpoints where specific state changes must have occurred.
- Let the model improve its own prompts and tools: an agent that exercised a flawed tool dozens of times and rewrote its description cut later task time by 40%.

## Anti-patterns

- Multi-agent for tasks with tight dependencies or little parallelism
- Vague delegation; no boundaries between workers
- Workers that return raw data instead of condensed findings
- 50 workers for a simple query; no effort rules
- Lead that does the exploration itself and runs out of context
- Plan held only in the lead's context
- Treating lead-prompt edits as local changes
- Relying only on automated judges

See `references/lead-agent-prompt.md` for a skeleton lead-agent prompt, the delegation template and a worker return contract.

## Sources

- How we built our multi-agent research system: https://www.anthropic.com/engineering/multi-agent-research-system
- Building effective agents (orchestrator-workers): https://www.anthropic.com/engineering/building-effective-agents
- Effective context engineering (sub-agent architectures): https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
