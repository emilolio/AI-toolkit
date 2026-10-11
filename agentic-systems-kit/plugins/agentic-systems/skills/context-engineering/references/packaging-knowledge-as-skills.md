# Packaging procedural knowledge as skills

A skill is a folder with at minimum a `SKILL.md` (YAML frontmatter + instructions) plus optional scripts, references and resources that an agent discovers and loads on demand. Skills let one general-purpose agent be specialised, composed and shared instead of building a bespoke agent per workflow. They are an open standard and complement MCP: MCP connects tools, skills teach multi-step workflows over them.

## When to use which mechanism

| Need | Mechanism |
|---|---|
| Convention that applies every turn | CLAUDE.md or a rule file |
| Convention that applies to one area of the codebase | path-scoped rule |
| Procedure or reference used only sometimes | skill |
| Deterministic computation, or work whose source/input should not enter context | script bundled in a skill (run, not read) |
| Side-effecting action the agent should take | tool (with permission handling) |
| Integration with an external service | MCP server, plus a skill if the workflow has steps |

## Structure

```
my-skill/
├── SKILL.md            frontmatter (name, description) + the procedure; keep under ~500 lines
├── references/         deeper material, one level deep, linked by name from SKILL.md
│   └── forms.md        split by context: if two topics rarely co-occur, keep them in separate files
└── scripts/            executed, not loaded into context; state clearly whether each is to be run or read
```

Frontmatter: `name` and `description` are the essentials (`description` is what triggers the skill). In Claude Code, further optional fields exist (`disable-model-invocation` for side-effecting workflows the user should start explicitly, `argument-hint`, `allowed-tools`, `model`, `effort`, `paths` and others); outside Claude Code only `name`, `description`, `license`, `compatibility`, `metadata` and `allowed-tools` are accepted. Keep names lowercase, hyphenated, specific (`pdf-form-filling`, not `helper`).

## Progressive disclosure

Only `name` + `description` of every installed skill sit in the system prompt at startup; the `SKILL.md` body loads when the skill is invoked; referenced files load when a step needs them. This makes bundled material effectively free until used, so write the description for triggering and keep the body for doing. After compaction, each invoked skill keeps only a bounded prefix, so durable rules still belong in CLAUDE.md.

## Writing the description

- Third person, concrete trigger terms a user or task would contain ("fills PDF forms", "designs tool schemas", "builds eval suites"), and when *not* to use it if a neighbouring skill overlaps.
- No pressure language ("ALWAYS use this"); it over-triggers.
- Install at the scope where the triggers are relevant: a skill whose description fires on "system prompt" will fire in every project if installed at user scope.

## Writing the body

- State actions directly; one default path with an explicit escape hatch.
- Explain the why for non-obvious constraints; justify constants in scripts.
- Do not explain what the model already knows; spend the tokens on what is specific.
- Use forward-slash paths; list dependencies; put time-sensitive instructions in a clearly marked section.
- Be explicit about whether a bundled script should be executed or read as reference.

## Build skills from observed gaps

1. Run the agent on representative tasks without the skill; note where it struggles or takes unexpected paths.
2. Write the minimal skill that closes the gap; test it with a fresh agent instance that did not write it.
3. After a success, ask the agent to record its effective approach and common mistakes into the skill; after a failure, ask it to reflect on what went wrong and propose an edit.
4. Build 3+ eval tasks per skill (should trigger / should not trigger / does the right thing) and re-run them when the skill or the model changes.
5. Watch real runs for over-reliance on a skill or on particular context.

## Security

Install only from trusted sources; skills run with your permissions. For anything less trusted, read every bundled file, inspect dependencies and resources (images, scripts), and flag any instruction or code that reaches external network endpoints.

## Sources

- Equipping agents for the real world with Agent Skills: https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
- Skills (Claude Code docs): https://code.claude.com/docs/en/skills
- Skill authoring best practices: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
