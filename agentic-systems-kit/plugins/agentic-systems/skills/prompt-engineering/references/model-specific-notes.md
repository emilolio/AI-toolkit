# Model-specific prompting notes

Deltas that apply to particular model families, checked against the provider guides in October 2026. These change with every model release: treat them as leads to verify on your eval, and re-read the linked guide when a new model ships.

## Where Anthropic and OpenAI guidance differs

| Topic | Anthropic (Claude) | OpenAI |
|---|---|---|
| Long-context placement | documents first, query last (up to ~30% better) | instructions at both start and end; if only one, above the context (GPT-4.1 guide) |
| Few-shot default | 3–5 diverse examples | zero-shot first for reasoning models; examples must match instructions exactly |
| Delimiters | XML tags | Markdown headers first, XML for bounded reference content; JSON did poorly for large document sets |
| Visible reasoning | asking current models to write reasoning in output may be declined; read thinking blocks | do not prompt reasoning models to think step by step |
| Prefill | unsupported from Claude 4.6 (400 error) | not offered; use structured outputs |
| Markdown default | varies by model (some under-format; remove anti-markdown blocks there) | reasoning models suppress Markdown unless the developer message starts with "Formatting re-enabled"; some newer models over-format |
| Instruction hierarchy | system prompt; for newer models add mid-conversation system messages rather than editing past turns (edits invalidate thinking blocks) | `instructions` / developer messages above user messages; `instructions` are not carried over with `previous_response_id`, so resend them |

Both agree: no CAPS or pressure language; explain reasons; positive instructions; structured outputs over prompt-only JSON; evals before and after every change.

## Claude (current generation)

- **Thinking**: adaptive thinking plus the `effort` parameter replaces fixed `budget_tokens` (rejected from 4.7). Thinking is always on or on by default for the 5.x models; leave room for it in `max_tokens`. On Opus 5, prefer thinking at low effort over disabling it (disabled thinking can leak tool calls or tags as text).
- **Sampling**: Sonnet 5 rejects non-default `temperature`, `top_p`, `top_k`.
- **Literalness**: Sonnet 5 does not generalise an instruction from one item to others; state scope.
- **Verbosity**: Opus 5 runs long and effort does not reliably shorten visible output; prompt for brevity and restate near the end of long prompts.
- **Self-verification**: Opus 5 already verifies its work; remove "double-check everything" instructions to avoid over-verification. Fresh-context verifier subagents beat self-critique.
- **Scope and delegation**: Opus 5 and Fable 5 tend to expand scope and over-delegate; add scope and subagent caps.
- **Autonomy**: Fable 5 occasionally stops to ask "Shall I…?"; add an autonomous-mode reminder. Do not show the model remaining-token counters.
- **Prompt length**: Fable 5 needs brief instructions; skills and prompts written for earlier models are often too prescriptive and can degrade output.
- **Tokeniser**: Sonnet 5 produces ~30% more tokens for the same text; re-tune `max_tokens` and budgets.
- **Parallel tools**: a `<use_parallel_tool_calls>` block drives parallel calls close to 100%.
- **Structured outputs**: `output_config.format` for JSON responses, `strict: true` on tools. Unsupported: recursive schemas and most numeric/string-length/array constraints. Limits per request (at time of writing): 20 strict tools, 24 optional parameters, 16 union parameters. Enum case can vary; compare case-insensitively. Changing the schema invalidates the prompt cache.

## OpenAI (current generation)

- **Reasoning effort**: `reasoning.effort` (low → max); some newer models do not accept `none`. When migrating, match the old model's effort before tuning anything else. Remove `temperature`/`top_p` when reasoning is on.
- **Agentic reminders (GPT-4.1 guide)**: persistence + tool-use + planning reminders together improved SWE-bench Verified by close to 20%; planning alone ~4%. Passing tools via the API field rather than the prompt gave ~2%.
- **Eagerness (GPT-5 guide)**: lower with effort, early-stop criteria and a tool-call budget; raise with persistence and no confirmation requests. Tool preambles (restate goal, plan, narrate, summarise) improve user-visible transparency.
- **State**: passing `previous_response_id` in the Responses API reuses reasoning and improved Tau-Bench Retail from 73.9% to 78.2% in the GPT-5 guide.
- **Verbosity**: `verbosity` parameter sets answer length (not reasoning); override per context in the prompt.
- **Conflicts**: the later instruction tends to win; contradictions waste reasoning tokens. Resolve with explicit precedence.
- **Prompts in code**: OpenAI now recommends keeping production prompts in application code; hosted prompt objects and the `v1/prompts` endpoint are being retired (shutdown announced for Nov 30, 2026), as is the dashboard prompt optimizer.

## Sources

- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5
- https://platform.claude.com/docs/en/build-with-claude/structured-outputs
- https://developers.openai.com/api/docs/guides/prompt-engineering
- https://developers.openai.com/api/docs/guides/reasoning-best-practices
- https://developers.openai.com/api/docs/guides/latest-model
- https://developers.openai.com/cookbook/examples/gpt4-1_prompting_guide
- https://developers.openai.com/cookbook/examples/gpt-5/gpt-5_prompting_guide
- https://developers.openai.com/cookbook/examples/gpt-5/gpt-5-2_prompting_guide
