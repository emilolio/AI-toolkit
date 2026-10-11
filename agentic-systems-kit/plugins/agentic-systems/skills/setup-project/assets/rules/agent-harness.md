# Harness and architecture conventions

Applies whenever the agent loop, orchestration, session handling, state persistence or verification steps are created or changed. For the reasoning, load `agent-architecture`, `agent-harness` and `multi-agent-orchestration`.

- Choose the least complex architecture that passes the eval: single call → prompt chain / routing / parallelisation → orchestrator-workers / evaluator-optimiser → autonomous agent.
- Every capability in the harness maps to one of three loop phases: gather context, take action, verify. If a step does none of these, question it.
- Every autonomous loop has stopping conditions: max turns, max cost, max wall-clock, and explicit human checkpoints for consequential actions.
- Durable state lives in files, git or a database. Sessions start by orienting (where am I, what was done, what is next) and end by committing, logging progress and leaving a mergeable state.
- Bound each session or subagent to one unit of work with an explicit effort budget.
- Specifications and test lists are tamper-resistant: the agent may flip a status flag but never deletes or edits requirements.
- Verification is layered: deterministic checks first (tests, linters, schema validation, state assertions), end-to-end/visual checks second, LLM-as-judge last.
- Subagents are filters, not relays: they explore in a clean context and return a condensed result with references to artifacts, not raw dumps.
- Delegation is precise: objective, output format, tools/sources to use, boundaries and effort budget. Vague delegation causes duplicated or missing work.
- Prefer code (scripts, typed wrappers, programmatic tool calls) over chains of model round-trips for loops, filtering, retries and data transformation.
- Production harnesses resume from the failure point, tell the model when a tool failed, retry deterministically, checkpoint periodically and trace every decision.
