---
name: agent-evals
description: Designing and running evaluations for agents - building task sets from real usage, writing unambiguous tasks with reference solutions, choosing graders (code-based, LLM-as-judge, human), grading outcomes rather than paths, capability vs regression suites, pass@k vs pass^k, trial isolation, efficiency metrics, LLM-judge hygiene, eval-driven development, and layering evals with production monitoring. Use when creating or extending an eval suite, deciding how to measure a prompt or tool change, validating a new model, or when an agent's quality is unclear or drifting.
---

# Evaluating agents

Evals are the only way to see regressions and behaviour changes before users do. Their value compounds over the agent's lifetime, they force the team to define what success means, and they let you adopt a new model in days instead of weeks. Start small, start early, grade outcomes, read the transcripts.

## 1. Vocabulary

| Term | Meaning |
|---|---|
| Task | one test: inputs plus success criteria |
| Trial | one attempt at a task; run several because outputs vary |
| Grader | scoring logic; a task can have several graders, each with several assertions |
| Transcript / trajectory | full record of outputs, tool calls, reasoning |
| Outcome | final environment state (the reservation exists in the database, not "the agent said it booked it") |
| Eval harness | runs tasks, manages concurrency and isolation, records, grades, aggregates |
| Agent harness | the scaffold under test; you always evaluate model + harness together |
| Suite | tasks sharing a goal |

## 2. Build the task set

- **Start with 20–50 simple tasks drawn from real failures and real usage.** Early on changes have large effects, so small samples are statistically enough; delaying makes eval-building harder because the system has grown.
- **Tasks are unambiguous.** Two domain experts should reach the same pass/fail verdict. Each task has a reference solution that passes all graders. A 0% pass rate across many trials usually means a broken task, not a weak agent.
- **Tasks are realistic and multi-step**: context plus a goal ("schedule a meeting with X next week, attach the notes, book a room"), using realistic data sources, not toy sandboxes. Single-step lookups with an explicit ID teach you little.
- **Balanced sets**: tasks where a behaviour should fire and tasks where it should not; one-sided sets cause one-sided optimisation.
- **Do not penalise instruction-following**: a task must not require exceeding a threshold the prompt only called a goal.
- **Hold out a test set** so tool and prompt refinements do not overfit the training evals.
- **Sources of tasks**: domain experts, product managers, support, sales, production transcripts, red-team findings. A dedicated team owns the eval infrastructure; everyone contributes tasks.

## 3. Grade outcomes, not paths

Rigid tool-sequence checks are brittle and punish valid creative solutions. Grade the final answer and the final state. Record expected tool sequences only as diagnostics, never as the pass criterion. For complex workflows define checkpoints where specific state changes must have occurred.

## 4. Choose graders (in preference order)

**Code-based (deterministic).** Exact / regex / fuzzy match; fail-to-pass and pass-to-pass tests; lint, type and security static analysis; outcome and state verification; transcript statistics (turn count, tool calls). Tolerant of formatting, punctuation and wording differences where those do not matter.

**Model-based (LLM-as-judge).** Rubric scoring, natural-language assertions, pairwise comparison, reference-based comparison, multi-judge consensus. Hygiene:
- structured rubric; one dimension per isolated judge call
- an "unknown" escape hatch so the judge does not guess
- partial credit for multi-component tasks
- resistant to gaming: passing must require actually solving the task
- calibrated against human experts before you trust it

**Human.** Subject-matter review, crowdsourcing, spot checks, A/B tests, inter-annotator agreement. Use sparingly, mainly to calibrate judges and catch what they miss (judges did not notice an agent preferring SEO content farms; humans did).

Scoring schemes: weighted with threshold, all-must-pass binary, or hybrid.

## 5. Graders by agent type

| Agent | Primary graders | Add as needed |
|---|---|---|
| Coding | unit tests for correctness + LLM rubric for code quality | static analysis, state checks, required-tool checks |
| Conversational | state check (ticket resolved) + transcript constraints (≤ N turns) + rubric (tone, grounding); usually a second LLM simulating the user | |
| Research | groundedness (claims tied to sources) + coverage (required facts present) + source quality; exact match where objectively answerable | |
| Computer / browser use | environment state (URL, page state, backend state, filesystem, config, DB, UI properties) | note the agent-side trade-off: DOM-based interaction is fast but token-heavy, screenshots are cheaper but lower-fidelity; it shapes efficiency metrics |

## 6. Capability vs regression

- **Capability evals**: low pass rate, a hill to climb, guide development.
- **Regression evals**: should sit near 100%; run in CI; block merges on drops.
- Saturated capability evals graduate into the regression suite. Take saturated public benchmarks at face value only with caution; scores on them tend to climb for reasons unrelated to your use case.

## 7. Reliability metrics

- **pass@k**: at least one success in k trials. Use when one win matters (a human picks the best).
- **pass^k**: all k trials succeed. Use for customer-facing reliability. 75% per-trial success gives pass^3 of about 42%.
- Run several trials per task; report distributions, not single runs.
- **Isolate every trial** in a clean environment. Shared files, caches, git history or memory make trials non-independent and correlate results.

## 8. Efficiency metrics

Track alongside accuracy: turns, tool calls, total tokens, cost per task, time to first and last token, tool error rate. Redundant calls point at tool pagination or limits; invalid-parameter errors point at descriptions.

## 9. Read the transcripts

Never trust a score without reading transcripts. Grader and task bugs are common: one model's score on a public benchmark went from 42% to 95% after fixing rigid numeric matching in the grader, ambiguous task specs, stochastic tasks and an over-constrained scaffold. Invest in a transcript viewer; eval frameworks are secondary and only as good as your tasks. Sample production transcripts weekly.

## 10. Eval-driven development

Write the eval for a planned capability before the agent can pass it. Treat eval maintenance like unit-test maintenance: tasks are code-reviewed, versioned, and pruned when stale.

## 11. Layer the methods (Swiss-cheese model)

| Layer | When |
|---|---|
| Automated evals | pre-launch and in CI on every prompt/tool/harness change |
| Production monitoring | continuously, for drift and anomalies |
| A/B tests | for big changes |
| User feedback | always, knowing it is sparse and skewed to severe issues |
| Manual transcript sampling | weekly |
| Systematic human studies | periodically, to calibrate judges |

## 12. Using the model to improve the eval loop

- Ask the agent to emit reasoning or feedback before tool calls (or enable interleaved thinking) so transcripts show *why*.
- Feed failing transcripts to a coding agent to diagnose contradictory descriptions, confusing schemas or missing context.
- Let an agent exercise a tool dozens of times and propose description rewrites; validate on the held-out set.

## Anti-patterns

- Rigid step-sequence checks
- Class-imbalanced sets
- Vague rubrics or ambiguous specs (become metric noise)
- State leaking between trials
- Grader bugs taken as agent failures
- Single-run scores
- Over-investing in frameworks instead of task quality
- Shipping prompt or tool changes without a before/after run

## Checklist for an eval suite

- [ ] 20–50 real tasks to start; held-out set defined
- [ ] Each task unambiguous with a reference solution that passes all graders
- [ ] Balanced should-fire / should-not-fire cases
- [ ] Outcome-based graders; deterministic where possible; judges calibrated
- [ ] Capability and regression suites separated; regression in CI
- [ ] Several isolated trials per task; pass@k and pass^k reported as appropriate
- [ ] Efficiency metrics tracked
- [ ] Transcript viewer available; weekly sampling scheduled
- [ ] Eval written before the next capability is built

See `references/eval-harness-skeleton.md` for a minimal harness structure and a judge rubric template.

## Sources

- Demystifying evals for AI agents: https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents
- Writing effective tools for agents (evaluation section): https://www.anthropic.com/engineering/writing-tools-for-agents
- How we built our multi-agent research system (evaluation section): https://www.anthropic.com/engineering/multi-agent-research-system
