---
name: init-marketplace
description: Scaffolds or extends a personal Claude Code plugin-marketplace repo - creates the .claude-plugin/marketplace.json, plugins/ layout, README and .gitignore in a new or existing repo, adds new plugins or skills to it, registers them, validates, and explains how to publish to GitHub and install from it. Run when starting a repo to hold reusable Claude material, or when adding a plugin or skill to one.
disable-model-invocation: true
argument-hint: "[init|add-plugin NAME|add-skill PLUGIN SKILL|status] [repo dir]"
---

# Set up or extend a plugin-marketplace repo

A marketplace repo is the home for reusable Claude material: each `plugins/<name>/` is a plugin (manifest + skills, agents, hooks), and `.claude-plugin/marketplace.json` registers them so any project can install one with `/plugin install <name>@<marketplace>`. The script does the deterministic file work; you handle the judgement calls.

```
<repo>/
├── .claude-plugin/marketplace.json    registry: name, owner, plugins[]
├── README.md
├── .gitignore
└── plugins/
    └── <plugin-name>/
        ├── .claude-plugin/plugin.json  manifest: name, version, description, author
        ├── skills/<skill>/SKILL.md     + references/, scripts/, assets/
        ├── agents/*.md                 optional
        └── hooks/hooks.json            optional
```

Script: `bash "${CLAUDE_SKILL_DIR}/scripts/scaffold.sh" <command> ...` (run with `--help` for usage).

## Commands

### `init [repo dir]` - start a marketplace repo

1. Ask for the marketplace name if `$ARGUMENTS` does not give one (default: directory name; lowercase, hyphens). This name is what users type after `@` when installing, so keep it short.
2. Run `scaffold.sh init --name <name> --owner "<owner>" <dir>`. It creates the registry, `plugins/`, README and `.gitignore`, and leaves existing files alone.
3. If the user wants this kit in the new repo, copy the `agentic-systems` plugin directory (the one this skill lives in: `${CLAUDE_PLUGIN_ROOT}`) into `plugins/agentic-systems/` and run `scaffold.sh register agentic-systems --desc "Design guidance for building agentic systems and harnesses"`.
4. `git init` if the user confirms; do not push or create a remote yourself (see Publishing).

### `add-plugin NAME [repo dir]` - add a plugin

Runs `scaffold.sh add-plugin NAME --desc "<one line>"`: creates the manifest with version `0.1.0`, an example skill, and registers it. Then: rename or replace `skills/example-skill`, fill in the author, and validate.

### `add-skill PLUGIN SKILL [repo dir]` - add a skill to an existing plugin

Runs `scaffold.sh add-skill PLUGIN SKILL --desc "<description>"`. Then write the body. Write the description in third person with concrete trigger terms and say when not to use it; it is the only part always in context. For side-effecting workflows add `disable-model-invocation: true`. Guidance for good skills is in the `context-engineering` skill's `references/packaging-knowledge-as-skills.md`.

### `status [repo dir]` - audit the registry

Shows the marketplace name, each registered plugin and whether its manifest exists, and any plugin directories not yet registered.

## After any change

1. `claude plugin validate ./plugins/<name>` for each touched plugin.
2. Bump `version` in that plugin's `plugin.json` when its contents changed; installed copies update only when the version changes.
3. Update the plugin list in the README.
4. Commit.

## Publishing and installing

Tell the user (do not run these without being asked):

```
# publish: create a GitHub repo and push
git remote add origin git@github.com:<user>/<repo>.git && git push -u origin main

# in any project, install from it
/plugin marketplace add <user>/<repo>
/plugin install <plugin-name>@<marketplace-name>
# or: claude plugin install <plugin-name>@<marketplace-name> --scope project

# try a plugin without installing
claude --plugin-dir ./plugins/<plugin-name>
```

Private repos work as long as the machine's git credentials can clone them. Pin a version for a team with `#<tag>` on the marketplace add.

## Report

A few lines: what was created or registered, validation result, the next step (write the skill body, bump version, push).
