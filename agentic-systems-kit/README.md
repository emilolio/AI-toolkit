# Agentic Systems Design Kit

Reusable, domain-agnostic guidance for building agentic systems and harnesses, packaged so that Claude Code (or the Claude Agent SDK) has it available when it matters. Distilled from Anthropic's engineering posts and developer docs, OpenAI's developer guides and the MCP specification: building agents, tool design, MCP servers, prompt engineering, context engineering, retrieval/RAG, long-running harnesses, multi-agent orchestration, evals, agent skills, sandboxing, prompt-injection defence and running LLM features in production.

This repo is a ready-made **Claude Code plugin marketplace**: push it to GitHub as-is and install from it. The kit itself is the `agentic-systems` plugin under `plugins/`; add further plugins beside it as your collection grows (`/agentic-systems:init-marketplace` scaffolds them). The plugin has three layers, chosen by how often the guidance is needed:

| Layer | Loads | Contents | Where it ends up |
|---|---|---|---|
| CLAUDE.md snippet | every turn | ~10 lines: three core principles and pointers to the skills and rules | appended to your project `CLAUDE.md` by `/agentic-systems:setup-project` |
| rules | every turn, or only when matching files are touched if you add `paths:` | one short conventions file per area | `.claude/rules/agent-*.md`, copied by `/agentic-systems:setup-project` |
| skills | on demand | 11 knowledge skills + 3 commands (setup, review, marketplace), each with deeper `references/` | stay in the plugin; available in every project where it is enabled |

The snippet is the pointer; the rules are the conventions; the skills are the reasoning. Only a skill's name and description sit in context until it is invoked. Keep the always-on layers short, and path-scope the rules in larger repos so they load only when the agent touches the relevant code.

## Install

### 1. Publish the marketplace (once)

Edit `.claude-plugin/marketplace.json`: set `name` (what users type after `@`; default `my-claude-kit`) and `owner.name`. Then:

```bash
git init && git add -A && git commit -m "Agentic systems kit"
git remote add origin git@github.com:<you>/<repo>.git && git push -u origin main
```

Private repos work as long as your machine's git credentials can clone them. Validate any time with `claude plugin validate .` (marketplace) and `claude plugin validate ./plugins/agentic-systems` (plugin).

### 2. Install the plugin in a project

In Claude Code:

```
/plugin marketplace add <you>/<repo>
/plugin install agentic-systems@my-claude-kit
```

Or from the shell: `claude plugin install agentic-systems@my-claude-kit --scope project` (enables it for everyone on that repo and keeps the skills out of unrelated projects). Use `--scope user` only if most of your projects are agent projects: the `context-engineering` and `prompt-engineering` skills trigger on prompt-writing tasks, which you may not want everywhere.

To try it without publishing: `claude --plugin-dir /path/to/agentic-systems-kit/plugins/agentic-systems`.

Skills are namespaced: `agentic-systems:agent-tool-design` etc. The model invokes the knowledge skills automatically when a task matches their description; the three commands run only when you type them: `/agentic-systems:setup-project`, `/agentic-systems:agent-design-review`, `/agentic-systems:init-marketplace`.

If you prefer no plugin, copy `plugins/agentic-systems/skills/*` into `~/.claude/skills/` (personal) or `.claude/skills/` (project) and drop the `agentic-systems:` prefix everywhere.

### 3. Apply it to a project

In Claude Code, inside the project:

```
/agentic-systems:setup-project
```

It previews, then copies the rules into `.claude/rules/`, appends the snippet to `CLAUDE.md` (creating it if needed), offers to path-scope the rules to your tool/prompt/eval directories, and reports whether the plugin is enabled persistently. It is idempotent: re-run it after updating the kit; files you have edited are kept and listed.

Manual equivalent:

```bash
K=/path/to/agentic-systems-kit/plugins/agentic-systems/skills/setup-project
bash $K/scripts/apply.sh --dry-run .     # preview
bash $K/scripts/apply.sh .               # apply
```

or copy `$K/assets/rules/*.md` into `.claude/rules/` and append `$K/assets/CLAUDE.md.snippet` to `CLAUDE.md` by hand. For user-wide rules, copy them into `~/.claude/rules/` instead.

To make a rule load only when relevant files are touched, add frontmatter with glob patterns, for example in `agent-tools.md`:

```yaml
---
paths:
  - "src/tools/**"
  - "mcp/**"
---
```

`paths` is the only frontmatter field read. Invalid YAML makes the rule unconditional.

### 4. Verify

Open a fresh session in the project and run `/context` to see the rules and CLAUDE.md loaded, then `/agentic-systems:agent-design-review` for a first audit.

### 5. Grow the collection

`/agentic-systems:init-marketplace add-plugin <name>` scaffolds a new plugin beside this one and registers it; `add-skill <plugin> <skill>` adds a skill to an existing plugin; `status` audits the registry. The same command's `init` creates this whole layout in any other repo.

### Claude Agent SDK projects

With the SDK's default setting sources, project `CLAUDE.md`, `.claude/rules/` and `.claude/skills/` are loaded automatically. For plugins, point the SDK at the plugin directory via the plugins option (see the SDK docs for the current parameter) or install via marketplace at user scope.

## Contents

```
agentic-systems-kit/                       (a plugin marketplace repo)
├── README.md
├── .gitignore
├── .claude-plugin/marketplace.json        registers the plugins below
└── plugins/
    └── agentic-systems/
        ├── .claude-plugin/plugin.json
        └── skills/
            ├── setup-project/             /setup-project: applies rules + snippet to a project
            │   ├── scripts/apply.sh       idempotent installer (--dry-run, --force)
            │   └── assets/
            │       ├── CLAUDE.md.snippet
            │       └── rules/
            │           ├── agent-tools.md     tool/MCP conventions
            │           ├── agent-prompts.md   prompt-writing conventions
            │           ├── agent-context.md   context conventions
            │           ├── agent-retrieval.md retrieval/RAG conventions
            │           ├── agent-production.md model, cost, reliability, guardrail, tracing, rollout conventions
            │           ├── agent-harness.md   architecture, state, verification, orchestration conventions
            │           ├── agent-safety.md    security and permission conventions
            │           └── agent-evals.md     evaluation conventions
            ├── init-marketplace/          /init-marketplace: scaffold a marketplace repo, add plugins/skills
            │   └── scripts/scaffold.sh
            ├── agent-design-review/       /agent-design-review: audit a codebase against the kit
            ├── agent-architecture/        autonomy ladder, workflow patterns, the loop, ACI, frameworks
            │   └── references/harness-sdk-shape.md
            ├── agent-tool-design/         tools, descriptions, results, errors, tool search, code execution, eval loop
            │   └── references/claude-tool-use-mechanics.md
            ├── mcp-server-development/    MCP primitives, transports, OAuth, MCP security, testing, shipping (spec 2026-07-28)
            │   ├── references/protocol-2026-07-28.md
            │   └── references/clients-and-tooling.md
            ├── prompt-engineering/        examples, output shape, structured outputs, reasoning modes, agentic blocks, debugging, migration
            │   ├── references/prompt-patterns.md
            │   └── references/model-specific-notes.md
            ├── context-engineering/       system prompts, context budget, retrieval, long-horizon techniques, caching
            │   ├── references/claude-context-mechanics.md
            │   └── references/packaging-knowledge-as-skills.md
            ├── agent-harness/             sessions, state files, orientation/hand-off, verification, production
            │   └── references/session-prompts.md
            ├── multi-agent-orchestration/ when to use, architecture, delegation, effort scaling, hand-offs
            │   └── references/lead-agent-prompt.md
            ├── agent-evals/               tasks, graders, pass@k vs pass^k, EDD, layering
            │   └── references/eval-harness-skeleton.md
            ├── rag-and-retrieval/         strategy ladder, chunking, contextual retrieval, hybrid + rerank, ACLs, citations, retrieval evals
            │   └── references/retrieval-mechanics.md
            ├── llm-production-ops/        model/effort choice, latency, cost, reliability, guardrails, tracing, rollout
            │   ├── references/provider-mechanics.md
            │   └── references/tracing-and-metrics.md
            └── agent-security/            injection, least privilege, sandboxing, confirmation, red-teaming
                └── references/injection-defence-patterns.md
```

Each `SKILL.md` keeps the principles provider-agnostic; Claude-API-specific mechanics live in `references/` so they can be updated independently. Every skill ends with source links the model can fetch when it needs the original.

## Customising

- **Add your own conventions** to the rules files (in the kit's `assets/rules/` if they should apply everywhere, or in a project's `.claude/rules/` copy if they are local; the setup script keeps locally edited files). Keep each under ~30 lines.
- **Project specifics** (where tools live, how to run evals) belong in the project `CLAUDE.md`, not in the kit.
- **New area?** Add a skill directory under `plugins/agentic-systems/skills/` with a `SKILL.md` whose description names concrete trigger terms, bump `version` in `plugin.json`, run `claude plugin validate`.
- **Keep it current.** The mechanics in `references/` reference specific API features and model behaviours that change. When a new engineering post or docs change appears, update the relevant reference file and the source list. The engineering blog index: https://www.anthropic.com/engineering

## Sources

- Building effective agents: https://www.anthropic.com/engineering/building-effective-agents
- Writing effective tools for agents: https://www.anthropic.com/engineering/writing-tools-for-agents
- Effective context engineering for AI agents: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Effective harnesses for long-running agents: https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
- How we built our multi-agent research system: https://www.anthropic.com/engineering/multi-agent-research-system
- Building agents with the Claude Agent SDK: https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk
- Code execution with MCP: https://www.anthropic.com/engineering/code-execution-with-mcp
- Introducing advanced tool use: https://www.anthropic.com/engineering/advanced-tool-use
- Demystifying evals for AI agents: https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents
- Equipping agents for the real world with Agent Skills: https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
- Beyond permission prompts (sandboxing): https://www.anthropic.com/engineering/claude-code-sandboxing
- Prompt injection defenses in browser use: https://www.anthropic.com/news/prompt-injection-defenses
- Introducing Contextual Retrieval: https://www.anthropic.com/news/contextual-retrieval
- Desktop extensions (MCPB): https://www.anthropic.com/engineering/desktop-extensions
- Model Context Protocol specification (2026-07-28): https://modelcontextprotocol.io/specification
- OpenAI, A practical guide to building agents: https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf
- OpenAI developer guides (prompt engineering, reasoning best practices, structured outputs, retrieval, optimizing LLM accuracy, latency optimization, production best practices, remote MCP): https://developers.openai.com/api/docs
- OpenTelemetry GenAI semantic conventions: https://github.com/open-telemetry/semantic-conventions-genai
- Claude developer docs (tool use, prompt engineering, caching, context editing, Agent SDK, Claude Code memory/skills/plugins): https://platform.claude.com/docs and https://code.claude.com/docs
