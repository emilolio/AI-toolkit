---
name: agent-harness
description: Building the harness around an agent so it works reliably over long horizons and in production - session design (initialiser vs worker sessions), externalising state to files and git, bounded units of work, orientation and hand-off routines, tamper-resistant specs and feature lists, layered self-verification, stopping conditions, checkpoints and resumption, retries, tracing and observability, deployment. Use when an agent must run longer than one context window, across many sessions, unattended, or when moving a prototype agent to production.
---

# Agent harnesses for long-running and production agents

Agents work in discrete sessions with no memory across them, and real projects do not fit in one context window. Compaction alone does not solve this because it does not reliably hand clear instructions to the next session. The harness must make every session behave like a disciplined engineer handing over a shift: **orient, do one bounded piece of work, verify it, leave things clean, write hand-off notes.** Anthropic's multi-agent research team reported that most of their engineering effort went into this "last mile" from prototype to reliable production.

The pattern is described with software vocabulary (git, init script, driving the UI) because that is where it was developed, but the unit of work can be anything bounded and verifiable: one section of a report, one dataset cleaned and validated, one batch of records processed with a reconciliation check. Map "run the smoke test" to "re-check the last verified output still holds" and "commit" to "write the artifact and log it".

## 1. Externalise state

The context window is working memory, not storage. Durable state lives in:

- **Version control** (git): history, revert, recover known-good states.
- **A progress log** (e.g. `progress.md` / `claude-progress.txt`): what each session did, decisions, open problems.
- **A structured spec / feature list** (JSON preferred: models are less likely to rewrite or clobber JSON than Markdown): one entry per unit of work with `category`, `description`, verification `steps`, and a `passes` flag.
- **A plan file** saved before deep work begins, so it survives context truncation.
- **Artifacts** (reports, data, code) written to storage, with lightweight references passed between agents instead of the content.
- **An init/run script** (`init.sh`) so no session re-derives how to start and test the system.

## 2. Separate initialisation from execution

- **Initialiser session** (once): expand the user's request into the granular spec, create the progress log, write the init script, make the first commit. Hundreds of features is normal for a large build.
- **Worker sessions** (repeated): consume the scaffolding. Same system prompt, tools and harness; only the initial user prompt differs.

## 3. Bound each session

One unit of work per session (one feature, one subtask, one research question) with an explicit effort budget. This counters the model's tendency to attempt everything at once and run out of context mid-implementation.

## 4. Orientation routine (start of every session)

1. Establish the working directory and environment (`pwd`, env checks).
2. Read recent history (`git log --oneline -20`) and the progress log.
3. Read the spec; pick the highest-priority unfinished item.
4. Run the init script and a basic end-to-end smoke test; fix anything a prior session broke **before** starting new work.

Be prescriptive about this in the system prompt or CLAUDE.md; a fresh window has nothing else to go on.

## 5. Hand-off routine (end of every session)

1. Verify the work as a user would (section 7).
2. Commit with a descriptive message.
3. Append a summary to the progress log: what was done, what was verified, what is unresolved.
4. Leave a mergeable state: no major bugs, orderly, documented, ready for the next session to start a new item without cleanup.

Define "clean state" concretely in the prompt.

## 6. Make the spec tamper-resistant

The spec is the contract. The agent may flip `passes` from false to true after verification; it must never delete, weaken or edit requirements or tests. State this explicitly. Combined with explicit pass flags this also cures **premature completion** (an agent sees existing progress and declares the whole project done).

## 7. Layered verification

| Layer | Examples | Notes |
|---|---|---|
| Rules-based | unit tests, type checks, linters, schema validation, state assertions (the row exists, the file parses) | cheapest, most reliable; prefer languages/tools that give richer feedback |
| End-to-end / visual | drive the real UI or API as a user would (browser automation, screenshots across viewports and states) | testing as a human user "dramatically improved" results over unit tests or curl alone; one screenshot carries limited information |
| LLM-as-judge | fuzzy criteria: tone, completeness, quality | costly and least robust; use where any gain matters and calibrate against humans |

Mark an item done only after the end-to-end check passes. Known weak spots: native browser modals the automation cannot see; purely visual verification.

## 8. Stopping conditions and checkpoints

- Max turns, max cost, max wall-clock, and a declared terminal state.
- Human checkpoints before consequential or irreversible actions (see `agent-security`).
- Periodic checkpoints of state so a crash resumes from the last good point rather than restarting.

## 9. Production reliability

- **Resume, don't restart.** Errors are expensive in long runs; resume from the failure point with the state the agent had.
- **Tell the model when a tool fails** so it can adapt (alternate tool, narrower query), and add deterministic retries for transient errors.
- **Prefer code for control flow.** Loops, polling, retries, filtering and transformation as scripts or programmatic tool calls, not chains of model round-trips.
- **Tracing.** Record every decision, tool call, result size and token count so you can diagnose why an agent failed without reading private content you should not store.
- **Deployment.** Agents are long-lived and stateful; roll out with gradual traffic shifting so in-flight runs are not disrupted; keep old and new versions running side by side during the shift.
- **Budgets per run** and alerts on anomalies (token spikes, runaway tool loops, repeated errors).
- **Isolation.** Each run in a clean environment; shared caches, files or git state between runs corrupt both production behaviour and evals.

## 10. Known open questions

- Whether one generalist worker agent beats specialised testing / QA / cleanup agents.
- How well the pattern transfers from software to other long-horizon domains (science, financial modelling). Treat it as a strong default, measure in your domain.

## Checklist for a long-running agent harness

- [ ] State files defined: progress log, structured spec with pass flags, plan, init script
- [ ] Initialiser vs worker prompts written; both share the harness
- [ ] Orientation and hand-off routines in the prompt / CLAUDE.md
- [ ] One unit of work per session, with an effort budget
- [ ] Spec is read-only except for status flags
- [ ] Verification is layered and end-to-end before marking done
- [ ] Stopping conditions, human checkpoints, periodic checkpoints
- [ ] Resume-from-failure, tool-failure signalling, deterministic retries
- [ ] Tracing of decisions, tokens and tool calls; anomaly alerts
- [ ] Clean, isolated environment per run

See `references/session-prompts.md` for prompt templates for initialiser and worker sessions.

## Sources

- Effective harnesses for long-running agents: https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
- How we built our multi-agent research system (production reliability section): https://www.anthropic.com/engineering/multi-agent-research-system
- Building agents with the Claude Agent SDK (verification section): https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk
