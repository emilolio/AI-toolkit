---
name: agent-architecture
description: Choosing and shaping the architecture of an agentic system - whether a task needs a single LLM call, a workflow (prompt chain, routing, parallelisation, orchestrator-workers, evaluator-optimiser) or an autonomous tool-using agent, how to structure the gather-context / take-action / verify loop, and when a framework helps or hurts. Use when designing a new agent, planning its components, reviewing an agent's overall design, or deciding whether to add agentic complexity.
---

# Agent architecture

An agentic system is an LLM using tools in a loop, plus the harness around it. The most reliable production systems are built from simple, composable patterns and gain complexity only when measurement shows it helps. This skill is about picking the right pattern and shaping the loop; the other skills in this kit cover tools, context, harnesses, orchestration, evals and security in depth.

## 1. Decide how much autonomy the task needs

Walk this ladder top to bottom and stop at the first rung that passes your eval:

| Rung | What it is | Use when |
|---|---|---|
| **Single augmented call** | One LLM call with retrieval, tools and/or examples | The task is well-defined and one call with the right context solves it |
| **Workflow** | LLM calls orchestrated through predefined code paths | The steps are predictable and you want predictability, testability and lower cost |
| **Autonomous agent** | The LLM decides its own steps and tool use, acting on environmental feedback | The problem is open-ended, the number of steps cannot be predicted, and you have a trusted environment plus feedback loops |

Agents trade latency, cost and compounding error risk for capability. Make that trade deliberately, with an eval that shows the gain.

Promising agent domains share four traits: they mix conversation and action, have clear success criteria, enable feedback loops (tests, tool results, state checks), and include meaningful human oversight.

## 2. Workflow patterns

Each pattern is a few lines of code when you call the model API directly. Pick by task shape.

- **Prompt chaining.** Fixed sequential subtasks, optionally with programmatic gates between steps. Trades latency for accuracy. Example: draft → check against criteria → rewrite.
- **Routing.** Classify the input, dispatch to a specialised prompt or model. Use when categories are distinct and classification is accurate. Example: easy queries to a small, fast model; hard ones to a strong model.
- **Parallelisation.** *Sectioning* (independent subtasks concurrently) or *voting* (same task several times, aggregated in code). Use for speed or confidence. A separate call that screens input for policy violations outperforms one call that does both the task and the screening.
- **Orchestrator-workers.** A central LLM decomposes the task dynamically, delegates to workers, synthesises results. Use when subtasks cannot be predicted ahead of time (multi-file code changes, multi-source research). See `multi-agent-orchestration`.
- **Evaluator-optimiser.** A generator and an evaluator loop. Use when clear evaluation criteria exist, outputs demonstrably improve with feedback, and the LLM can produce that feedback.

## 3. The agent loop

Every capability in a harness should map to one of three phases. If a component does none of these, question why it exists.

1. **Gather context.** Agentic search over a structured filesystem or data store (grep, glob, targeted reads) first; semantic/vector search only when you need speed or query variety, because it is less accurate, harder to maintain and less transparent. Subagents for parallel exploration and context isolation. Compaction when the window fills.
2. **Take action.** Custom tools as the primary verbs; a shell and scripts for flexible one-offs; code generation for complex, repeatable or precise operations; MCP for standardised integrations with auth handled.
3. **Verify.** Layered: rules-based feedback (tests, linters, schema validation, state assertions) → visual / end-to-end checks → LLM-as-judge for fuzzy criteria. Build the feedback loop into the harness; do not rely on the model's self-assessment alone.

Then repeat until a stopping condition is met.

A good default mental model: **give the agent a computer** (shell, filesystem, read/write/search) and let it work the way a skilled human would, rather than wiring up a bespoke pipeline for each capability.

## 4. Design the loop with guardrails

- Stopping conditions: max iterations, max cost, max wall-clock time, and a terminal state the agent can declare.
- Human checkpoints: at task clarification, before consequential actions, and when confidence is low. Define what "consequential" means in code, not just in the prompt.
- Ground truth every step: the agent should read tool results and environment state rather than assume its action succeeded.
- Transparency: expose planning steps explicitly (a task list, a plan file) so humans and evals can inspect them.
- Sandboxed testing before trusted deployment. See `agent-security`.

## 5. The agent-computer interface (ACI)

Tool definitions deserve as much attention as the main prompt. Teams that optimised SWE-bench agents spent more time on tools than on the system prompt. Principles that belong here at the architecture level (details in `agent-tool-design`):

- Put yourself in the model's position: if a tool is unclear to you after reading its definition, it is unclear to the model.
- Choose output formats close to what the model sees naturally in text. Avoid formats that need counting or escaping (unified diffs with line counts, code inside JSON strings).
- *Poka-yoke* the tools: change argument designs so mistakes become hard to make (e.g. requiring absolute paths eliminated a whole class of errors after the model changed directories).

## 6. Frameworks

- Start by calling the model API directly; most patterns are a few lines.
- If you adopt a framework or SDK, understand the code underneath. Hidden prompts and responses make debugging harder and wrong assumptions about internals are a common source of errors.
- Reduce abstraction layers when going to production.
- A harness SDK that provides the loop, built-in tools, subagents, hooks, permissions, sessions and compaction can save you from rebuilding the plumbing; keep your own code focused on tools, prompts and evals. See `references/harness-sdk-shape.md` for what a mature harness provides and how to configure one.

## 7. Diagnostic questions when the agent underperforms

1. Is information missing? Could search/retrieval tools be restructured to surface it?
2. Does a repeated failure admit a formal rule that a tool or hook can enforce?
3. Would more useful or more creative tools let the agent approach the problem differently?
4. Has performance drifted as features were added? Build a representative eval set from real usage.
5. Is the prompt at the wrong altitude - too vague, or a brittle rule stack?
6. Is the architecture more autonomous than the task requires?

## Checklist for a new agent design

- [ ] Autonomy ladder walked; the chosen rung is justified by an eval or a clear task-shape argument
- [ ] Every component mapped to gather / act / verify
- [ ] Stopping conditions and human checkpoints defined in code
- [ ] Tool set is minimal, distinct, namespaced (see `agent-tool-design`)
- [ ] Context plan: what is static, what is retrieved just in time, how long tasks are managed (see `context-engineering`)
- [ ] State persistence and session handoff designed (see `agent-harness`)
- [ ] Trust boundaries and permissions defined (see `agent-security`)
- [ ] 20–50 real eval tasks exist before building (see `agent-evals`)

## Sources

- Building effective agents: https://www.anthropic.com/engineering/building-effective-agents
- Building agents with the Claude Agent SDK: https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk
- Effective context engineering for AI agents: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
