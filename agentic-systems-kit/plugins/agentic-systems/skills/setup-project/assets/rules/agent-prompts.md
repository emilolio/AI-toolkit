# Prompt conventions

Applies whenever a prompt, prompt template, structured-output schema or model setting is created or changed. For the reasoning, the patterns and model-specific notes, load the `prompt-engineering` skill.

- Before editing a prompt, write the success criteria and keep 10–20 real test inputs (including edge cases and unanswerable ones). Run them before and after every change; change one thing at a time.
- Write for a capable colleague with no context: task, audience, purpose, what "done" looks like. Give the reason behind every non-obvious rule.
- Say what to do, not only what to avoid. Make scope explicit ("apply to every section"); audit for contradictory instructions.
- No pressure language (CAPS, "CRITICAL", "you MUST", bribes): it over-triggers on current models. Use calm, conditional wording ("Use this when…").
- Separate instructions, context, examples and inputs with consistent XML tags or headers. Long documents go first, the question last.
- When code parses the output, use structured outputs (schema-constrained decoding), not "respond in JSON". Allow `null` for missing values; never put reasoning in a schema field; validate business rules in code.
- Give concrete length budgets ("3–6 sentences", "≤5 bullets") and ask for the answer first.
- Reasoning models: state the goal and criteria, set effort; do not instruct "think step by step" or ask for reasoning in the output. Manual chain of thought only on non-reasoning calls, with the answer in its own tag.
- Examples are copied closely: 1–5 diverse examples that show only the wanted behaviour, wrapped in `<example>` tags.
- Agent prompts state the action posture (act vs propose), persistence, tool discipline (look up rather than guess; ask when an input is missing), grounded status reports and scope limits.
- Prompts live in the repo as versioned templates with named variables, static content first and variables last; log the prompt version with every call.
- On a model switch: baseline, swap only the model with matched effort, then remove obsolete workarounds one at a time.
