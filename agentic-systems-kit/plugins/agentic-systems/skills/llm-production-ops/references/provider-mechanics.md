# Provider mechanics for production

Claude and OpenAI specifics behind `llm-production-ops`. Checked against the docs in October 2026. Prices, limits, tiers and model names change often; re-check the linked page before relying on a number.

## Claude API

**Model choice and effort**
- Anthropic's guidance: most workloads start on the current top general model (Opus at time of writing), then lower effort or downgrade; or start on Haiku for high-volume simple work and upgrade only where needed. "Tuning effort is often a better lever than switching models."
- `effort` levels: `low`, `medium`, `high`, `xhigh`, `max`. It affects thinking, tool calls and text. It is a behavioural signal, not a token budget; `max_tokens` is the hard cap on thinking + text (start around 64k at `xhigh`/`max`). Changing top-level effort between requests invalidates the prompt cache; keep it constant within a conversation.
- Fixed thinking `budget_tokens` is rejected on 4.7+ models; use adaptive thinking with effort.
- Measured cascade results (Anthropic, their benchmarks): advisor pattern +1.7 points at ~2.1× cost; orchestrator pattern ~50% cheaper on average with some quality loss on very large corpora. Measure on your own traffic.

**Cost**
- Message Batches: 50% off; most finish in under 1 h, hard 24 h expiry; up to 100,000 requests / 256 MB per batch; results kept 29 days, unordered (match on `custom_id`); errored/expired requests not billed. Stacks with caching (cache hits are best-effort in batch; use the 1 h TTL for shared prefixes).
- Prompt caching: writes 1.25× base input (5 min TTL) or 2× (1 h TTL); reads ~0.1× base or lower on newer models; minimum cacheable length ~512 tokens on current models; up to 4 breakpoints. Cache reads do not count toward input-token rate limits on most models (2M ITPM at 80% hit rate ≈ 10M effective).
- Fast mode (research preview, selected Opus models): up to ~2.5× output tokens/second at premium price; separate rate limit; switching speed invalidates the cache; not available in batch.
- Priority Tier: no longer sold to new buyers at time of writing; `service_tier` reports what served the request.
- Token counting endpoint is free with its own rate limit; useful for routing and budgeting. Newer tokenisers can produce ~30% more tokens for the same text.
- Spend: per-organisation monthly caps by usage tier; a cap-hit 429 (`enforced_spend_limit_reached`) has no `retry-after` and must not be retried. Workspace spend limits are available.
- Usage and Cost Admin API: usage grouped by model, workspace, key, tier; daily cost in USD; data within ~5 min.

**Reliability**
- SDKs retry connection errors, 429 and 5xx with exponential backoff (2 retries by default), honouring `retry-after`; configure `max_retries`.
- 529 `overloaded_error`: API-wide load; back off. 429 can also come from acceleration limits on sudden ramps. 504: use streaming. Errors can arrive as stream events after a 200.
- Non-streaming requests expected to exceed ~10 minutes are rejected by the SDKs; stream or batch them.
- Stop reasons: `end_turn`, `max_tokens`, `model_context_window_exceeded`, `pause_turn` (server tools; resend unchanged, capped), `refusal` (HTTP 200 with `stop_details.category`), `tool_use`, `stop_sequence`.
- Refusal fallback: server-side `fallbacks` (beta) to a default or named list of models; only classifier refusals trigger it, not 429/529/5xx. Size the fallback model's rate limits. Discard partial streamed output after a mid-stream refusal.
- Structured outputs (`output_config.format`) and `strict: true` tools use constrained decoding; refusals and `max_tokens` stops can still break conformance. Forced `tool_choice` is rejected on some newer models; use `auto` with strict tools.
- Model IDs from 4.6 onward are pinned snapshots, including dateless IDs; older aliases float. Retirement notice is at least 60 days.

**Claude Agent SDK**
- Budgets: `max_turns` / `maxTurns` and `max_budget_usd` / `maxBudgetUsd`; subagents get their own `maxTurns`. No top-level session timeout by default.
- `total_cost_usd` is a client-side estimate: monitor with it, bill from the Usage and Cost API.
- Hosting: persist sessions with a session store (local state is lost on restart); pin sessions to containers by session ID; start around 1 GiB RAM / 5 GiB disk / 1 CPU per agent; token cost usually dominates container cost by an order of magnitude.

## OpenAI

**Model choice**: the practical agents guide is capability-first: baseline with the most capable model, hit the accuracy target, then swap in smaller models. Model-selection guide: keep the lightest model and reasoning setting that meets the quality bar. Fine-tuning (SFT/DPO/RFT) is in wind-down for new users at time of writing.

**Latency (seven principles)**: process tokens faster (smaller models, Predicted Outputs on supported models), generate fewer tokens (~50% fewer output tokens ≈ ~50% lower latency), use fewer input tokens (50% shorter prompt ≈ 1–5% faster), make fewer requests, parallelise, make users wait less (streaming), don't default to an LLM.

**Cost**
- Batch API: 50% off, 24 h window; up to 50,000 requests / 200 MB per batch; separate rate-limit pool.
- Prompt caching: automatic from 1,024 tokens; cached input heavily discounted; track `usage.input_tokens_details.cached_tokens`; use `prompt_cache_key` to improve hit rates.
- Flex processing: batch-rate pricing for synchronous calls, slower, may return 429 "Resource Unavailable" (not billed); use long timeouts.
- Priority/fast processing: premium price; requests may be downgraded to standard during fast ramps.
- Rate limits count the larger of `max_tokens` and estimated tokens: set `max_tokens` close to need. Ramp gradually (guidance at time of writing: once at high volume, grow ≤50% per 15 minutes).

**Reliability**: exponential backoff with jitter, `Retry-After` as a minimum, cap attempts and total time; disable SDK retries if you run your own loop; failed requests still count toward per-minute limits; never retry quota/billing errors. Separate staging and production projects with their own limits.

**Guardrails (Agents SDK)**: input guardrails run on the first agent, output guardrails on the last, tool guardrails around each function tool (not hosted tools or handoffs). `run_in_parallel=True` is the default (faster; the agent may act before the tripwire); set it to `False` where tools have side effects. Tripwires raise `InputGuardrailTripwireTriggered` / `OutputGuardrailTripwireTriggered` and tool equivalents. Moderation endpoint (`omni-moderation-latest`) is free for text and images; treat category scores as signals and recalibrate thresholds. Pass a hashed `safety_identifier` per end user.

**Tracing (Agents SDK)**: spans for agent, generation, function tool, guardrail and handoff; `group_id` ties traces to a conversation; `trace_include_sensitive_data` defaults to **true**: turn it off unless content capture is approved; call `flush_traces()` in short-lived workers; redact in the exporter.

## Sources

- https://platform.claude.com/docs/en/about-claude/models/choosing-a-model
- https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence
- https://platform.claude.com/docs/en/build-with-claude/effort
- https://platform.claude.com/docs/en/build-with-claude/batch-processing
- https://platform.claude.com/docs/en/build-with-claude/prompt-caching
- https://platform.claude.com/docs/en/build-with-claude/fast-mode
- https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons
- https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback
- https://platform.claude.com/docs/en/build-with-claude/token-counting
- https://platform.claude.com/docs/en/api/errors
- https://platform.claude.com/docs/en/api/rate-limits
- https://platform.claude.com/docs/en/api/service-tiers
- https://platform.claude.com/docs/en/manage-claude/usage-cost-api
- https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions
- https://platform.claude.com/docs/en/about-claude/model-deprecations
- https://code.claude.com/docs/en/agent-sdk/hosting
- https://code.claude.com/docs/en/agent-sdk/cost-tracking
- https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf
- https://developers.openai.com/api/docs/guides/latency-optimization
- https://developers.openai.com/api/docs/guides/model-selection
- https://developers.openai.com/api/docs/guides/batch
- https://developers.openai.com/api/docs/guides/prompt-caching
- https://developers.openai.com/api/docs/guides/flex-processing
- https://developers.openai.com/api/docs/guides/rate-limits
- https://developers.openai.com/api/docs/guides/production-best-practices
- https://developers.openai.com/api/docs/guides/moderation
- https://openai.github.io/openai-agents-python/guardrails/
- https://openai.github.io/openai-agents-python/tracing/
