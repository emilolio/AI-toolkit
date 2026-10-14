---
name: prompt-engineering
description: Writing, debugging and iterating the prompts inside an LLM app or agent - context and motivation, few-shot examples, delimiters, output format and length, structured outputs, reasoning modes (chain of thought vs thinking vs reasoning models), prompt chaining, long-document prompts, agentic prompt blocks, templates and versioning, model migration and meta-prompting. Use when drafting or editing any prompt or template, when output is generic, inconsistent, misformatted, too long, hallucinated or ignores instructions, or when switching models. For what enters the context window see context-engineering; for tool descriptions see agent-tool-design.
---

# Prompt engineering

A prompt is a spec for a capable colleague who has none of your context. Write it for that reader, then treat it as code: define success first, change one thing at a time, measure before and after. Most "prompt problems" are missing context, contradictions, or a format the model has to guess. Newer models follow instructions literally and need fewer tricks; much classic prompting advice (shouting, heavy role-play, forced step-by-step reasoning, prefill) now hurts or is unsupported.

`context-engineering` covers *what* enters the window (altitude, budgets, ordering, caching, compaction). This skill covers *how to write* the words; where the two differ on a wording detail, this skill's newer, model-aware guidance applies.

## 1. Before writing: success criteria and a test set

- Write down what a good output is: specific, measurable criteria, usually several at once (accuracy, format validity, tone, latency, length).
- Collect 10–20 real inputs, including edge cases and inputs where the right answer is "I don't know" or a refusal. This is your prompt's test suite (grow it into a proper eval with `agent-evals`).
- Not every failure is a prompt problem. Latency, cost and some capability gaps are fixed by choosing a different model, retrieval or a tool.

## 2. The core moves

| Move | How | Watch out |
|---|---|---|
| **Be clear and direct** | State the task, the audience, the output, and what "done" means. Number steps when order or completeness matters. Ask explicitly for above-and-beyond effort if you want it | Golden rule: if a colleague with minimal context would be confused, so is the model |
| **Give the why** | "Output goes to a text-to-speech engine, so never use ellipses" beats "NEVER use ellipses" | Models generalise from the reason; bare rules get applied too narrowly or too broadly |
| **Say what to do** | "Write flowing prose paragraphs" beats "don't use markdown". Match your prompt's own style to the output you want | Negative-only instructions push the model to a different unwanted default |
| **Set scope explicitly** | Literal models do not generalise an instruction from one item to the rest. Say "apply this to every section" | Contradictions are resolved unpredictably (often the later instruction wins); audit for them |
| **Role in one line** | "You are a senior tax accountant reviewing filings." Spend the remaining words on task context | Heavy persona prompting is mostly unnecessary |
| **Separate parts with delimiters** | XML tags or Markdown headers for instructions, context, examples, inputs; consistent names; nest documents | For short prompts plain prose is fine; JSON is a poor wrapper for large documents. Delimiters organise; they are not a security boundary: user-supplied or third-party text can still carry instructions (`agent-security`) |
| **Calm wording** | "Use this tool when…" | Both providers' current guides warn that CAPS, "CRITICAL", "you MUST", bribes and threats cause over-application |

## 3. Examples

- Use examples when instructions alone give inconsistent shape or tone. Start with zero or one (especially on reasoning/thinking models) and grow to 3–5 diverse examples covering edge cases when the eval shows drift; wrap them in `<example>` tags.
- Examples are copied closely: phrases, length, structure. Make sure they show only what you want, vary them, or tell the model to vary wording.
- Positive examples of the desired style beat lists of "don't"s.
- Examples must agree exactly with the instructions; a mismatch hurts more on reasoning models.

## 4. Output shape

- **Structured outputs** (constrained decoding against a JSON schema) whenever code parses the result. This beats "respond only in JSON" prompting and removes the need for strongly worded format instructions. Keep schemas simple, put guidance in field descriptions, mark fields required, allow `null` for missing values instead of guessing. Do not ask for reasoning inside a schema field. Still handle refusals and truncation before parsing.
- **Classification**: an enum field (via structured output or a tool) rather than free text.
- **Extraction**: record only what the source states. Missing → `null`; hedged or approximate values ("maybe 4 lb", "a few") → keep the value with a qualifier field (`approximate: true`, or the verbatim phrase) instead of rounding to certainty; ambiguous → `null` plus a note. A `source_quote` field per important value makes fabrication visible and checkable in code.
- **Mixed outputs** (data for code + prose for a person): either one schema with a prose field, or two calls (extract, then write from the extracted data). Prefer two calls when the parts have different success criteria or the prose must not influence the data.
- **Length**: give a concrete budget ("3–6 sentences", "≤5 bullets", "one sentence for yes/no questions") and, for long prompts, restate the tone/length preference near the end. Effort/reasoning settings do not reliably control visible length, and schemas cannot enforce string length, so check hard limits in code.
- **Lead with the outcome**: ask for the answer or verdict first, then supporting detail.
- Prefilling the assistant turn is unsupported on Claude models from 4.6 onward (400 error). Use structured outputs for format, "respond directly without preamble" for preambles, and put continuation text in the user turn.

## 5. Reasoning

| Model mode | Prompting |
|---|---|
| Reasoning / thinking model (adaptive or extended thinking, OpenAI reasoning models) | State the goal and the success criteria; let it plan. "Think thoroughly" beats a hand-written step list. Do not say "think step by step" and do not ask it to write its reasoning in the output (can hurt, and current Claude models may decline). Control depth with the effort parameter. Read thinking blocks/summaries for debugging |
| Non-reasoning call | A short chain-of-thought instruction helps on multi-step problems: reason in `<thinking>`, answer in `<answer>`, parse only the answer. Refine the reasoning instruction from eval failures |

Sampling parameters (temperature, top_p) are rejected or ignored on many current reasoning-class models; get variety through the prompt ("propose 4 distinct directions") instead.

## 6. Decompose when one prompt does too much

- **Chain** when you need to inspect, log or gate intermediate outputs, or each step has a different success criterion: draft → review against criteria → revise, as separate calls. Each prompt does one thing well.
- Do not chain what a single call already does reliably; it adds latency and cost. Thinking models and subagents handle much multi-step reasoning internally.
- **Verification** works better as a separate fresh-context call than as "check your work" inside the same prompt; strong models already self-check and over-verify when told to.

## 7. Long inputs

- Put long documents at the top, wrapped with index and source, and the question/instructions at the end (Anthropic: up to ~30% better). OpenAI's guidance for its models: instructions at both start and end. When unsure, put the key instruction at both ends and test.
- Ask the model to extract relevant quotes first, then answer from them; give explicit permission to say the documents do not contain the answer.

## 8. Agentic prompts

Agents need a few explicit blocks that one-shot prompts do not. Templates in `references/prompt-patterns.md`.

- **Action posture**: say whether to act by default or to propose and wait; "can you…" from the user means do it (or not). Name the destructive actions that always need confirmation.
- **Persistence**: keep going until the task is fully resolved; do not stop to ask permission for reversible steps; document assumptions instead.
- **Tool discipline**: use tools for fresh facts, IDs and URLs rather than guessing; if a required input is missing, ask instead of inventing it ("must call a tool" without a fallback causes hallucinated arguments).
- **Grounded progress claims**: before reporting status, check each claim against a tool result; this nearly eliminated fabricated status reports in Anthropic's testing.
- **Eagerness budget**: for quick tasks give a tool-call budget and early-stop criteria; for deep tasks ask for persistence and parallel tool calls.
- **Scope**: do what was asked; no extra features, files or refactors. Current models tend to expand scope or over-delegate unless told.
- Pass tools through the API's tool field, never pasted into the prompt.

## 9. Prompts as code

- Keep production prompts in the repo: templates with named variables (`{{customer_message}}`) wrapped in tags, code-reviewed, versioned, tested in CI with the eval set, rolled out behind flags. Platform-hosted prompt objects are convenient for prototyping; do not make them the source of truth.
- Static content first, variables last, so caching works (`context-engineering` §6).
- Log prompt version with every call so a regression can be traced to a change.

## 10. Debugging

| Symptom | Try |
|---|---|
| Generic, bland output | Add audience, purpose and a concrete example of good output |
| Off-target | State the goal and why; remove contradictory or stale instructions |
| Inconsistent format | Structured outputs or a schema; one canonical example |
| Too long / too short | Concrete length budget; lead-with-outcome instruction; restate near the end |
| Ignores an instruction | Check for a contradiction or a later conflicting line; give the reason; move it next to where it applies |
| Over-applies an instruction | Remove CAPS/pressure language; give "when not to" |
| Makes things up | Allow "I don't know"; ground in provided documents; quote first; use tools for facts |
| Suggests instead of acting | Imperative verbs; explicit action-posture block |
| Misses findings in review tasks | Do not ask for "only high-severity"; ask for full coverage with severity and confidence, filter in a second pass |
| Regressed after a model switch | See migration below |

## 11. Migrating to a new model

1. Baseline the eval on the old model.
2. Switch only the model; keep the prompt, and match the reasoning-effort setting.
3. Re-run, read transcripts, then remove workarounds the new model no longer needs (pressure language, forced CoT, redundant "verify your work", anti-markdown blocks) one at a time, re-running after each.
4. Re-tune `max_tokens` and length budgets (tokenisers change) and check for parameters the new model rejects.

Model-specific deltas for current Claude and OpenAI models are in `references/model-specific-notes.md`; they go stale quickly, so re-check the linked guides.

## 12. Using a model to improve prompts

- Ask a strong model to critique the prompt against failing transcripts: "Which phrases should be added or removed to fix this behaviour? Keep the prompt mostly intact." Minimal edits are easier to evaluate than rewrites.
- Generated or "improved" prompts are usually longer and slower and can regress on specific inputs. Always run the eval and read the outputs before adopting one.

## Checklist for a prompt

- [ ] Success criteria written; 10–20 test inputs including edge and unanswerable cases
- [ ] Task, audience, purpose and done-condition stated; reasons given for non-obvious rules
- [ ] Positive instructions; no contradictions; scope explicit; no CAPS/pressure language
- [ ] Delimited sections; long documents first, question last
- [ ] Output shape fixed by schema or concrete example and length budget
- [ ] Reasoning handled per model mode; no forced CoT on reasoning models
- [ ] Agent prompts: action posture, persistence, tool discipline, grounded status, scope
- [ ] Template versioned in the repo with variables last; eval run before and after every edit

## Sources

- Claude prompting best practices: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- Prompt engineering overview: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/overview
- Define success criteria and develop tests: https://platform.claude.com/docs/en/test-and-evaluate/develop-tests
- Structured outputs (Claude): https://platform.claude.com/docs/en/build-with-claude/structured-outputs
- Best practices for prompt engineering (Claude blog): https://claude.com/blog/best-practices-for-prompt-engineering
- OpenAI prompt engineering guide: https://developers.openai.com/api/docs/guides/prompt-engineering
- OpenAI reasoning best practices: https://developers.openai.com/api/docs/guides/reasoning-best-practices
- OpenAI structured outputs: https://developers.openai.com/api/docs/guides/structured-outputs
- OpenAI GPT-4.1 prompting guide (agentic reminders): https://developers.openai.com/cookbook/examples/gpt4-1_prompting_guide
- OpenAI GPT-5 prompting guide (eagerness, preambles, metaprompting): https://developers.openai.com/cookbook/examples/gpt-5/gpt-5_prompting_guide
