# Prompt patterns

Copy-and-adapt blocks for the moves in `prompt-engineering`. Each is a starting point: keep only the blocks a failure on your eval set calls for, and reword them for your domain.

## System prompt skeleton

```xml
<role>You are {{one line: who, for whom}}.</role>

<context>
{{What the product is, who the users are, what they need the output for, and why
the constraints below exist. This is the section most prompts are missing.}}
</context>

<instructions>
1. {{Step or rule, with the reason when it is not obvious.}}
2. ...
</instructions>

<output_format>
{{Concrete shape: length budget, sections, lead with the answer. Or "Respond using
the provided schema."}}
</output_format>

<examples>
  <example>
    <input>...</input>
    <output>...</output>
  </example>
</examples>
```

Per-request material (documents, user data) goes in the user turn, after the static prompt, in tags such as `<documents>` or `<customer_message>`.

## Long-document user turn

```xml
<documents>
  <document index="1">
    <source>{{path or URL}}</source>
    <document_content>{{text}}</document_content>
  </document>
</documents>

First, find the passages relevant to the question and copy them word for word into
<quotes> tags. Then answer the question using only those quotes. If the documents do
not contain the answer, say so plainly.

<question>{{question}}</question>
```

## Manual chain of thought (non-reasoning calls only)

```
Work through the problem inside <thinking> tags, then give only the final answer
inside <answer> tags.
```

Parse `<answer>` in code; never show `<thinking>` to end users. Do not use this with reasoning models or extended/adaptive thinking.

## Agentic blocks

Use only the ones a failure calls for.

**Act by default**
```xml
<default_to_action>
When the user asks for a change, make it rather than describing it. Requests phrased
as questions ("can you…?") are requests to act. If intent is genuinely ambiguous,
pick the most useful reasonable interpretation, state it in one line, and proceed.
</default_to_action>
```

**Propose first** (advisory agents)
```xml
<do_not_act_before_instructions>
Do not modify files or external systems unless the user explicitly asks for that
change. Default to explaining options and recommending one.
</do_not_act_before_instructions>
```

**Persistence**
```
Keep working until the user's request is fully resolved before ending your turn. Do
not stop to ask for permission for reversible steps; note the assumption you made
and continue. Only end your turn when the task is done or you are blocked on
information only the user has.
```

**Tool discipline**
```
If you are unsure about file contents, current data, IDs or URLs, use your tools to
check rather than guessing. If a required input is missing and no tool can provide
it, ask the user for it instead of inventing a value.
```

**Reversibility and confirmation**
```
Local, reversible actions (reading, editing files in the workspace, running tests)
are fine without asking. Before anything destructive or visible to others (deleting
data, force-pushing, sending messages, spending money, changing permissions),
describe the action and wait for confirmation.
```
Enforce the same list in code; see `agent-security`.

**Grounded status reports**
```
Before reporting progress or completion, check each claim against a tool result from
this session (test output, file contents, API response). Report only what you
verified; mark anything unverified as such.
```

**Scope control**
```
Do what was asked and nothing more: no extra features, refactors, files or
abstractions unless they are required for the requested change. Mention worthwhile
follow-ups in one line at the end instead of doing them.
```

**Parallel tool calls**
```xml
<use_parallel_tool_calls>
When several tool calls do not depend on each other, make them all in the same turn
rather than one after another.
</use_parallel_tool_calls>
```

**Eagerness budget** (fast tasks)
```
Gather only enough context to act. Use at most {{N}} tool calls before answering. Stop
searching as soon as you can name the exact change or answer. If still uncertain,
proceed with the best answer and say what you are unsure about.
```

## Review/critique prompts

For code review, document review or audits, do not ask for "only important issues"; literal models then under-report. Ask for coverage and filter afterwards:

```
Report every issue you find. For each, give severity (high/medium/low), confidence
(high/medium/low), location, and a one-line fix. A separate step will filter the list.
```

## Meta-prompt for improving a prompt

```
Here is a prompt and transcripts where it produced the wrong behaviour.

<prompt>{{current prompt}}</prompt>
<failures>{{transcripts with what was wrong}}</failures>
<desired_behaviour>{{what should have happened}}</desired_behaviour>

Explain which parts of the prompt most likely caused the failures (contradictions,
missing context, misleading examples, over-strong wording). Then propose the
smallest set of edits that fixes them, as a list of exact additions and deletions.
Keep the rest of the prompt unchanged.
```

Evaluate the edited prompt on the full test set, not only on the failures.

## Sources

- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- https://developers.openai.com/cookbook/examples/gpt4-1_prompting_guide
- https://developers.openai.com/cookbook/examples/gpt-5/gpt-5_prompting_guide
