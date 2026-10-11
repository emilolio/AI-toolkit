---
name: agent-design-review
description: Audits an agentic system's codebase against the kit's design principles (architecture, tools, context, harness, orchestration, evals, security) and produces a prioritised findings report. Run before merging changes to an agent's core.
disable-model-invocation: true
argument-hint: "[path to the agent code, default: current project]"
---

# Agent design review

Review the agent system at `$ARGUMENTS` (default: the current project) against the principles in this kit. Produce a findings report, not a rewrite. Do not change code unless the user asks afterwards.

## Procedure

1. **Map the system.** Locate: the agent loop / harness entry point; tool definitions (functions, schemas, MCP servers); system prompts and prompt templates; context handling (caching, compaction, memory, retrieval); orchestration (subagents, workers); state persistence; evals; permission / safety code. Write a one-paragraph description of the architecture as you understand it.

2. **Load the kit skills you need** for the areas present (they live alongside this one in the same plugin: `agent-architecture`, `agent-tool-design`, `context-engineering`, `agent-harness`, `multi-agent-orchestration`, `agent-evals`, `agent-security`). Use each skill's checklist as the audit list.

3. **Audit each area.** For every checklist item record: pass / partial / fail / not applicable, the evidence (file and line), and the concrete fix. Pay particular attention to:
   - tool overlap, vague descriptions, unbounded results, opaque errors
   - instructions that live only in the first user message; per-request values in the cached prefix; no compaction strategy for long tasks
   - missing stopping conditions; state only in the conversation; no orientation / hand-off routine
   - vague delegation; workers returning raw data
   - no evals, or evals that grade paths; no before/after discipline
   - untrusted content in system or user text; secrets in the sandbox; destructive tools without confirmation; policy only in prompts

4. **Prioritise.** Order findings by (impact on reliability or safety) × (ease of fix). Mark the top five as "do first".

5. **Report** in this shape:

```
# Agent design review: <system name>
Architecture summary: …

## Do first
1. <finding> - <why it matters> - <fix> - <file:line>
…

## Findings by area
### Tools  (n pass / n partial / n fail)
…
### Context and prompts
…
### Harness and state
…
### Orchestration
…
### Evals
…
### Security
…

## What is already good
…

## Suggested next eval tasks
<3-5 tasks that would catch the top findings if they regress>
```

Keep the report factual; cite files. Where a principle does not apply to this system, say so briefly rather than forcing a finding.
