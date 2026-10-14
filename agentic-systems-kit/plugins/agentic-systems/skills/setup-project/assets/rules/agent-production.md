# Production conventions

Applies whenever a model, effort setting, routing rule, retry/timeout policy, guardrail, budget, tracing or rollout path for an LLM feature or agent is created or changed. For the reasoning and provider specifics, load the `llm-production-ops` skill.

- Model and effort are chosen by the eval. Tune effort/reasoning before switching models; keep the lightest setting that meets the quality bar. Cascades and routers are shadow-tested against the single-model baseline.
- Pin model snapshots in production. Version model ID, effort, prompt, tools, schemas and retrieval settings together and log that version on every call.
- Budgets live in code: `max_tokens` per call, max turns and max spend per agent run, per-tenant quotas, spend alerts.
- Stream user-facing output; cache static prefixes; send non-interactive work (evals, backfills, enrichment) to batch APIs.
- Retries use exponential backoff with jitter, honour `retry-after`, and are capped; never retry quota, spend-limit or validation errors unchanged. Every call has an explicit timeout.
- Check the stop reason on every response: truncated output is flagged, a truncated tool call is never executed, refusals are not retried unchanged.
- Validate structured output against business rules in code; re-prompt once with the error, then fail loudly.
- Define fallbacks for refusal, overload and timeout; each fallback model has its own eval baseline and rate-limit headroom. Side-effecting tools take idempotency keys.
- Guardrails are layered (rules, input classifiers, tool risk ratings, output checks, human escalation). Where tools have side effects, guardrails block before the agent acts rather than running in parallel. A guardrail error is not a pass.
- Trace every model and tool call (OpenTelemetry GenAI conventions): model, effort, config version, tokens incl. cached and reasoning, cost, TTFT, latency, stop reason, errors. Record content only when the pipeline is approved to store it.
- Model and prompt changes roll out offline eval → shadow → canary → ramp, with per-version dashboards and a ready rollback.
