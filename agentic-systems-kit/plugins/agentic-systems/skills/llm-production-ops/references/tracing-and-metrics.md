# Tracing and metrics for LLM apps and agents

Span and metric names from the OpenTelemetry GenAI semantic conventions (repository `open-telemetry/semantic-conventions-genai`, status **Development** as of October 2026: names can still change, so pin the semconv version you emit). Using them lets any OTel backend group and chart LLM traffic without custom parsing.

## Span tree for one agent run

```
invoke_agent support-agent                    (INTERNAL, or CLIENT if the agent is remote)
├── chat claude-opus-5-5                      (CLIENT)  model call, turn 1
├── execute_tool search_orders                (INTERNAL)
├── chat claude-opus-5-5                      (CLIENT)  model call, turn 2
├── execute_tool refund_order                 (INTERNAL)
│   └── (your HTTP/DB spans)
└── chat claude-opus-5-5                      (CLIENT)  final answer
```

Propagate W3C trace context so the agent run nests under the web request that started it. Subagent runs nest under the parent's tool span.

## Inference span (one model call)

Name: `{gen_ai.operation.name} {gen_ai.request.model}`, kind CLIENT.

| Attribute | Requirement | Notes |
|---|---|---|
| `gen_ai.operation.name` | required | `chat`, `embeddings`, … |
| `gen_ai.provider.name` | required | `anthropic`, `openai`, … |
| `gen_ai.request.model` | conditionally required | requested model ID |
| `gen_ai.response.model` | recommended | model that actually served |
| `gen_ai.response.id` | recommended | join key for user feedback |
| `gen_ai.response.finish_reasons` | recommended | stop reasons; alert on refusal / length spikes |
| `gen_ai.request.max_tokens`, `gen_ai.request.temperature` | recommended | |
| `gen_ai.request.reasoning.level` | recommended | effort / reasoning effort |
| `gen_ai.request.stream` | conditionally required | |
| `gen_ai.conversation.id` | conditionally required | only a real conversation/session ID |
| `gen_ai.usage.input_tokens` | recommended | **includes** cached tokens (for Anthropic: input + cache read + cache write) |
| `gen_ai.usage.output_tokens` | recommended | includes reasoning tokens |
| `gen_ai.usage.cache_read.input_tokens`, `gen_ai.usage.cache_write.input_tokens`, `gen_ai.usage.reasoning.output_tokens` | recommended | subsets of the above |
| `gen_ai.response.time_to_first_chunk` | recommended | streaming TTFT |
| `error.type` | conditionally required | on failure |

Add your own: prompt/config version, tenant (pseudonymous), route, retry count, cost.

## Agent and tool spans

- `invoke_agent {gen_ai.agent.name}`; `create_agent {name}`; `invoke_workflow {gen_ai.workflow.name}`; `plan {name}`.
- `execute_tool {gen_ai.tool.name}` (INTERNAL) with `gen_ai.tool.call.id`, `gen_ai.tool.type` (`function`, `extension`, `datastore`), `error.type`.

## Content attributes (opt-in only)

`gen_ai.input.messages`, `gen_ai.output.messages`, `gen_ai.system_instructions`, `gen_ai.tool.definitions`, `gen_ai.tool.call.arguments`, `gen_ai.tool.call.result`.

The conventions say not to capture these by default; in production, store content in an approved store with retention limits and record a reference on the span. Check SDK defaults:
- Claude Agent SDK / Claude Code telemetry: structure only by default; content via `OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_TOOL_DETAILS`, `OTEL_LOG_TOOL_CONTENT`, `OTEL_LOG_RAW_API_BODIES` (leave unset unless approved). Enable with `CLAUDE_CODE_ENABLE_TELEMETRY=1` and OTLP exporters; export failures are silent unless `CLAUDE_CODE_OTEL_DIAG_STDERR=1`. Shorten export intervals for short-lived jobs.
- OpenAI Agents SDK: `trace_include_sensitive_data` defaults to true; set `OPENAI_AGENTS_TRACE_INCLUDE_SENSITIVE_DATA=false` unless approved.

## Metrics

| Metric | Type |
|---|---|
| `gen_ai.client.inference.duration` | histogram, seconds |
| `gen_ai.server.time_to_first_token`, `gen_ai.server.time_per_output_token` | histogram |
| `gen_ai.client.inference.usage.{input_tokens, output_tokens, cache_read.input_tokens, cache_write.input_tokens, reasoning.output_tokens}` | counter, by `gen_ai.token.modality` |
| `gen_ai.invoke_agent.duration`, `gen_ai.invoke_agent.inference_calls`, `gen_ai.invoke_agent.tool_calls` | histogram |
| `gen_ai.execute_tool.duration` | histogram |

Set operation, provider, model and tool name at span creation so head samplers can use them. Keeping 100% of error and refusal traces while sampling successes needs **tail sampling** (decided after the trace completes, e.g. in an OTel collector), because a head sampler decides before the outcome is known.

`gen_ai.server.time_to_first_token` is measured at the server; also record time to first visible output at the client, which in agent loops includes tool round-trips.

## Starter dashboard

- Latency: p50/p95 TTFT and total duration by route and model
- Volume and cost: requests, tokens (in/out/cached/reasoning), cost per request, per tenant, per day
- Cache-hit ratio = cache_read / input_tokens
- Finish-reason mix; alerts on refusal, length truncation, context overflow
- Errors: 429 / 5xx / overloaded rates, retries per request, fallback rate
- Agents: turns per run, tool calls per run, tool error rate, runs hitting max turns or budget
- Guardrails: trip rate by guardrail
- Quality: online judge scores on sampled traffic, thumbs-down rate joined on `gen_ai.response.id`

## Sources

- https://github.com/open-telemetry/semantic-conventions-genai (docs/gen-ai: client-inference.md, gen-ai-spans.md, gen-ai-agent-spans.md, gen-ai-metrics.md, anthropic.md)
- https://code.claude.com/docs/en/agent-sdk/observability
- https://openai.github.io/openai-agents-python/tracing/
