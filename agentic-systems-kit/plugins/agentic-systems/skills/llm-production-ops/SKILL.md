---
name: llm-production-ops
description: Running LLM features and agents in production - model and effort selection, routing and cascades, latency and cost levers (streaming, caching, batch, tiers, budgets), reliability (retries, rate limits, timeouts, stop reasons, truncation, refusals, fallbacks, schema validation), runtime guardrails, observability with OpenTelemetry GenAI tracing, and model/prompt versioning and rollout. Use when taking an LLM feature from prototype to production, choosing or switching models, when it is slow, expensive, flaky, rate-limited or truncating, or when adding monitoring, guardrails or a model upgrade path.
---

# LLM production operations

A prototype proves the model *can* do the task. Production needs it to do the task at a known cost, latency and failure rate, observably, and to survive model upgrades. Everything here assumes an eval set exists (`agent-evals`): every model, effort, prompt or routing change is a before/after measurement on that set, then a shadow or canary on real traffic.

## 1. Choose the model and effort

**Pick a starting point deliberately.**

| Strategy | Start with | Then | Fits |
|---|---|---|---|
| Capability-first (both providers' default for most work) | the most capable model | hit the quality bar, then lower effort or swap in smaller models while the eval holds | new, complex or agentic tasks; unknown difficulty |
| Efficiency-first | the smallest fast model | move up only where the eval fails | high-volume simple tasks, tight latency, prototypes on a budget |

- **Tune effort/reasoning before switching model.** Effort (or reasoning effort) changes thinking, tool calls and text together; it is often a better lever than a different model. Keep the lightest setting that meets the quality bar. Re-sweep it on every model migration; do not carry settings over.
- **Cascades, when one model is not the right price point:**
  - *Advisor*: a cheap executor does the work and escalates hard decisions to a frontier model. Fits serial work with a few hard spots. Consult rate is fragile (executors under-call unless prompted); measure it.
  - *Orchestrator*: a frontier model plans and delegates bulk work to cheaper workers. Fits many independent pieces. See `multi-agent-orchestration`.
  - *Router*: a classifier (or token count) sends easy requests to a small model and hard ones to a large one.
  - Shadow-test any cascade against the single-model baseline before cutover.
- **Fine-tuning** is for behaviour (format, tone, narrow classification) that prompting cannot reach, or to make a small model viable for one narrow task. It is not for missing knowledge (`rag-and-retrieval`). Availability varies by provider; check before planning on it.
- **Don't default to an LLM.** Hard-coded responses, lookup tables and caches of previous answers beat any model on latency and cost.

## 2. Latency

In rough order of payoff:

1. **Generate fewer tokens.** Output dominates latency: halving output roughly halves latency, while halving input saves only a few percent. Concrete length budgets, structured fields instead of prose, lower effort.
2. **Stream** anything a human waits on; show progress and intermediate steps. Use streaming for long requests anyway (non-streaming requests near the 10-minute mark are rejected or time out).
3. **Make fewer sequential calls.** Merge steps that always run together into one call returning named fields; run independent calls in parallel; run cheap classifiers speculatively alongside the main call.
4. **Smaller or faster model / lower effort** for the latency-critical path; fast/priority output modes where offered (they raise output speed, not time to first token, at a premium).
5. **Cache the static prefix** (lowers time to first token on long prompts; `context-engineering` §6).
6. **In agent loops, user-visible latency is dominated by round-trips before the first text**: each tool call adds a model turn. Cut turns (merge tools, parallel tool calls, prefetch likely data, cache tool results such as weather or catalogue lookups with a TTL), stream a short status or plan line before slow tools, and measure time to first *visible* output at the client, not only the server's time to first token.
7. Measure time to first visible output and total latency separately, at p50 and p95, per route.

Get the prompt working first, then optimise latency; optimising early hides what good output looks like.

## 3. Cost

| Lever | Typical effect | Use when |
|---|---|---|
| **Batch API** | ~50% off, results within 24 h (often < 1 h) | anything not user-facing: evals, backfills, enrichment, contextualisation, nightly jobs |
| **Prompt caching** | cached input billed at a small fraction (≈10% or less) of base; often also raises effective rate limits | any repeated prefix above the model's minimum cacheable length (varies by model and provider, roughly 0.5–4k tokens; check yours): system prompts, tools, documents, history. Changing tools, model, effort or speed mode mid-conversation invalidates the cache |
| **Effort / reasoning level** | fewer thinking and output tokens | after the quality bar is met |
| **Smaller model / cascade** | large per-token savings | where the eval holds |
| **Output length control** | proportional | always, via prompt length budgets and lower effort. `max_tokens` is a truncation cap: OpenAI counts it against rate limits (set it near need); Anthropic counts only generated tokens, so leave headroom for thinking and avoid truncation |
| **Flex / low-priority tiers** | batch-like price, slower, may 429 | latency-tolerant online work |
| **Fewer tokens in** | proportional on input | prune retrieval results, clean HTML, drop unused tools |

**Unit economics and capacity**: cost per conversation × expected volume, and peak requests and tokens per minute (from daily volume and peak-hour share) against your rate limits; request limit increases ahead of launch.

Put **budgets in code**: per-request `max_tokens`, per-run max turns and max spend for agents, per-user (or per-tenant) daily quotas, workspace or project spend limits, and alerts on anomalies. Client-side cost estimates from SDKs are for monitoring; bill users from the provider's usage/cost reports. Tokenisers change between model generations (one change produced ~30% more tokens for the same text), so recount before re-using cost estimates.

## 4. Reliability

- **Retries**: exponential backoff with jitter on 429, 5xx, overloaded (529) and connection errors; honour `retry-after`; cap attempts and total time. Use either the SDK's built-in retries or your own loop, not both. Never retry quota/billing/spend-limit errors or 400s unchanged.
- **Rate limits**: read the rate-limit response headers; ramp new traffic gradually (sudden spikes trip acceleration limits); separate pools for batch vs online; cache-hit tokens often do not count against input limits.
- **Timeouts**: set them explicitly per call; stream long generations; bound agent runs with max turns (most agent SDKs have no overall timeout by default).
- **Check the stop reason on every response** (a 200 is not success):

| Stop reason | Action |
|---|---|
| natural end | parse and validate |
| max tokens | output truncated: raise the limit or continue; a truncated tool call must be retried, never executed; flag truncation to the user |
| context window exceeded | treat as truncated; compact or split |
| pause (server tools) | resend to continue, with a cap |
| refusal | do not retry unchanged; fall back (below) or explain to the user; discard partial streamed output |

- **Structured output**: constrained decoding guarantees the schema, not the business rules. Validate rules in code; on failure re-prompt once with the validation error, then fail loudly. Refusals and truncation can still yield non-conforming output.
- **Fallbacks**: define what happens when the primary model refuses, is overloaded or times out. Provider-side fallback models (where offered) typically cover refusals only; overload and timeouts need a secondary model or provider at your gateway, a cached or degraded answer, or a clear error. Each fallback model needs its own eval baseline and enough rate-limit headroom.
- **Overload protection**: a circuit breaker per model/provider (stop sending after repeated failures, probe to recover), queueing with a max wait, load shedding of low-priority traffic, and a designed degraded mode users see.
- **Idempotency**: model calls are not idempotent and providers mostly offer no idempotency key. A retried turn produces new tool-call IDs, so derive the key from the business action (user + resource + slot + date), or use a prepare/confirm pair where the confirm step consumes a single-use token. Retry a failed *model call* freely; never blindly re-run a whole *turn* whose tools may already have executed: reload the tool results from your store instead.
- **Errors mid-stream** can arrive after a 200; handle them in the stream consumer.

## 5. Runtime guardrails

Layer several cheap checks; no single one is sufficient. They sit alongside authentication, authorisation and access control, not instead of them.

| Layer | Examples | Runs |
|---|---|---|
| Rules | input length limits, blocklists, regex, allowed-value checks | before the model, in code |
| Input classifiers | relevance (on-topic?), safety/jailbreak, moderation | small fast model or moderation endpoint, in parallel with or before the main call |
| Tool safeguards | rate each tool low/medium/high risk (read vs write, reversibility, permissions, money); high-risk needs confirmation or human approval | in the harness (`agent-security`) |
| Output checks | PII filter, moderation, groundedness/citation check, brand/policy check, schema and business-rule validation | after the model, before the user or the next tool |
| Human escalation | after repeated failures, before high-risk actions, on low confidence | in the workflow |

- **Parallel vs blocking**: running a guardrail in parallel with the main call saves latency but the main call may already have spent tokens or run tools when the tripwire fires. Run input guardrails in parallel for turns that can only read, and block before any side-effecting tool executes (gate the tool call, not every turn).
- **Confirmation** for high-risk tools comes from the end user in the product UI (propose → user confirms → server executes), as `agent-security` §5 requires; operator approval is an additional control for actions beyond the user's own authority.
- A guardrail that errors is "unknown", not "pass". Decide the fail-open vs fail-closed policy per guardrail.
- Hallucination reduction: allow "I don't know", ground in provided documents, quote-then-answer, cite and verify, best-of-N disagreement as a signal. These reduce, not eliminate.
- System-prompt leak hardening degrades performance; prefer output screening and keeping secrets out of the prompt.
- Start with privacy and content safety; add guardrails for edge cases you observe; tune safety and UX together.

## 6. Observability

Trace every model call and tool call as spans under one trace per user request or agent run. Follow the OpenTelemetry GenAI semantic conventions (still marked Development) so any backend can read them. Names and attributes are in `references/tracing-and-metrics.md`.

**Record per model call**: provider, model ID, effort/reasoning level, prompt/template version, input/output/cached/reasoning tokens, cost, time to first token, total latency, stop reason, error type, retry count, response ID. **Per tool call**: tool name, call ID, duration, error, result size. **Per run**: turns, total tokens and cost, outcome.

**Privacy**: record structure by default, not content. Capture prompts, outputs and tool arguments only when the pipeline is approved to store them (check default settings: some SDKs capture content unless you turn it off), with retention limits and redaction in the exporter. Prefer storing content separately and referencing it from spans. Tag runs with tenant/user identifiers in hashed or pseudonymous form.

**Dashboards and alerts**: p50/p95 latency and TTFT per route and model; tokens and cost per request and per tenant; cache-hit rate; stop-reason distribution (alert on spikes in refusals, truncation, context overflow); 429/5xx and retry rates; guardrail trip rate; fallback rate; tool error rate; eval scores of sampled production traffic.

**Close the loop**: capture user feedback (thumbs, edits, escalations) with the trace or response ID; sample production traces weekly and grow the eval set from failures; run online LLM-judge evals on a sample, calibrated against human labels.

## 7. Versioning and rollout

- **Pin model snapshots** in production; treat floating aliases as development-only. Even a pinned ID can shift slightly when the serving stack changes, so keep monitoring.
- **Version the whole config together**: model ID, effort, prompt template, tool definitions, schemas, retrieval settings. Log the config version on every call.
- **Track deprecations**: providers give notice (Anthropic: at least 60 days) before retiring a model; find remaining usage by model from usage reports and migrate well before the date.
- **Rollout path** for any model or prompt change: offline eval → shadow traffic (log only) → canary at 1–5% with per-version dashboards → ramp, respecting provider ramp-rate guidance. Keep the previous version deployable for instant rollback. Separate staging and production projects/keys with their own limits.
- On migration: re-sweep effort, recount tokens, re-tune `max_tokens`, check for parameters the new model rejects, remove prompt workarounds the new model no longer needs (`prompt-engineering` §11).

## Checklist before launch

- [ ] Model and effort chosen by eval; cascade (if any) shadow-tested against the single-model baseline
- [ ] Output length budgeted; streaming on user-facing paths; static prefix cached; offline work on batch
- [ ] Budgets in code: max tokens, max turns, max spend per run and per tenant; spend alerts
- [ ] Retries with backoff and caps, explicit timeouts, rate-limit handling and ramp plan
- [ ] Every stop reason handled; truncated tool calls never executed; schema + business-rule validation
- [ ] Fallback path for refusal, overload and timeout, each with an eval baseline
- [ ] Layered guardrails; blocking mode where tools have side effects; fail-open/closed decided
- [ ] Tracing of model and tool spans with tokens, cost, latency, stop reason and config version; content capture off unless approved
- [ ] Dashboards and alerts; feedback capture joined to traces; weekly transcript sampling
- [ ] Pinned model IDs; versioned config; shadow → canary → ramp rollout with rollback

See `references/provider-mechanics.md` for Claude and OpenAI specifics (batch and cache pricing, service tiers, effort levels, error codes, stop reasons, refusal fallbacks, agent SDK budgets) and `references/tracing-and-metrics.md` for OpenTelemetry GenAI span and metric names.

## Sources

- Choosing a model: https://platform.claude.com/docs/en/about-claude/models/choosing-a-model
- Optimizing for cost and intelligence (advisor/orchestrator patterns): https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence
- Reduce latency: https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-latency
- Effort: https://platform.claude.com/docs/en/build-with-claude/effort
- Batch processing: https://platform.claude.com/docs/en/build-with-claude/batch-processing
- Handling stop reasons: https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons
- Refusals and fallback: https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback
- Errors and rate limits: https://platform.claude.com/docs/en/api/errors and https://platform.claude.com/docs/en/api/rate-limits
- Strengthen guardrails (hallucinations, consistency, jailbreaks, prompt leak): https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations
- Model IDs and deprecations: https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions and https://platform.claude.com/docs/en/about-claude/model-deprecations
- Agent SDK hosting, cost tracking, observability: https://code.claude.com/docs/en/agent-sdk/hosting
- OpenAI, A practical guide to building agents: https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf
- OpenAI, Latency optimization: https://developers.openai.com/api/docs/guides/latency-optimization
- OpenAI, Production best practices: https://developers.openai.com/api/docs/guides/production-best-practices
- OpenAI, Rate limits: https://developers.openai.com/api/docs/guides/rate-limits
- OpenAI Agents SDK guardrails and tracing: https://openai.github.io/openai-agents-python/guardrails/
- OpenTelemetry GenAI semantic conventions: https://github.com/open-telemetry/semantic-conventions-genai
