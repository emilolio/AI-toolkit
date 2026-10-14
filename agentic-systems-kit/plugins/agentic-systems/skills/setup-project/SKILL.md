---
name: setup-project
description: Applies the agentic-systems kit to a project - installs the agent-* rules into .claude/rules/, appends the design snippet to CLAUDE.md, optionally path-scopes the rules, checks plugin enablement and verifies the result. Run once per project, and again after updating the kit.
disable-model-invocation: true
argument-hint: "[project root, default: current directory] [--dry-run]"
---

# Set up a project with the agentic-systems kit

Apply the kit's always-on layers to the project at `$ARGUMENTS` (default: current working directory). The script does the deterministic file work; you handle the judgement calls below.

## 1. Preview

Run a dry run first so the user sees what will change:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/apply.sh" --dry-run <project root>
```

Show the output. If the project already has `.claude/rules/agent-*.md` files that differ from the kit, the script keeps them; tell the user and ask whether to replace them (`--force` keeps a `.bak` of each).

## 2. Apply

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/apply.sh" [--force] <project root>
```

The script is idempotent: it adds missing rule files, updates unchanged ones, never appends the snippet twice (it looks for the `## Agentic system design` header), and creates `CLAUDE.md` if the project has none.

## 3. Path-scope the rules (offer, do not assume)

Rules load on every turn unless scoped. For a small repo that is fine. For a larger repo, offer to scope each rule to the code it governs. Look for likely directories (`tools/`, `mcp/`, `prompts/`, `agents/`, `harness/`, `evals/`, `tests/`) and propose, for example:

```yaml
---
paths:
  - "src/tools/**"
  - "mcp/**"
---
```

at the top of `.claude/rules/agent-tools.md`. Apply only the mappings the user confirms. `agent-safety.md` should usually stay unscoped. Remember `paths` is the only frontmatter field read, and invalid YAML makes a rule unconditional, so validate the YAML after editing.

## 4. Check plugin persistence

The script reports whether `agentic-systems` is enabled in project or user settings. If it is not, the skills are available in this session only. Tell the user the install command for their setup:

- marketplace install, project scope (recommended): `claude plugin install agentic-systems@<marketplace> --scope project`
- or `claude --plugin-dir <kit>/plugin` per session
- or copy `<kit>/plugin/skills/*` into `.claude/skills/` and drop the `agentic-systems:` prefix from the review command in `CLAUDE.md`

Do not edit `settings.json` yourself; the install command does it correctly.

## 5. Tailor the snippet (optional)

The snippet is generic. If the user wants, add one or two project-specific lines under it in `CLAUDE.md`: where tools live, how to run the evals, which review command to run before merging. Keep the generic principles intact so future kit updates stay comparable.

## 6. Verify and report

- List `.claude/rules/` and show the tail of `CLAUDE.md`.
- Tell the user to run `/context` in a fresh session to confirm the rules and CLAUDE.md are loaded.
- Suggest `/agentic-systems:agent-design-review` as the first use.

Report in a few lines: what was added, what was kept, what was scoped, and whether the plugin persists.

## Updating later

Re-run this skill after pulling a new kit version. Unchanged kit files update in place; files the user edited are kept and listed, so they can merge by hand or use `--force`. New rule files are added automatically. The `CLAUDE.md` snippet is never re-appended once its header exists, so after a kit update compare the project's `## Agentic system design` section with `assets/CLAUDE.md.snippet` and offer to replace that section (e.g. to pick up newly added skill names).
