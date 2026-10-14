---
name: mcp-server-development
description: Building, securing, testing and shipping Model Context Protocol (MCP) servers - tools vs resources vs prompts, structured output, annotations, stateful handles, elicitation, tasks and MCP Apps, stdio vs Streamable HTTP, OAuth 2.1 (protected resource metadata, audience validation, no token passthrough), MCP security (confused deputy, tool poisoning, rug pulls), the stateless 2026-07-28 spec revision, MCP Inspector, and connecting servers to Claude Code, the Claude API and OpenAI. Use when creating, changing, migrating or adding auth to an MCP server or client, exposing an API to agents over MCP, or vetting a third-party MCP server. Pair with agent-tool-design for tool naming, descriptions and results.
---

# MCP server development

MCP is the standard plug between agents and external systems: a server exposes capabilities, any compliant host (Claude Code, Claude apps and API, ChatGPT and OpenAI's APIs, IDEs) can use them. The protocol handles discovery, transport and auth; it does **not** make tools well designed or safe. Design the tools with `agent-tool-design`, then use this skill for the protocol, security and shipping.

**Spec revision note.** The current revision is **2026-07-28**, a deliberate breaking change: the protocol is stateless (no `initialize` handshake, no sessions, no server-to-client requests). Clients and SDKs speaking 2025-11-25 and earlier remain common, so most servers should serve both eras for now. Details in `references/protocol-2026-07-28.md`; re-check https://modelcontextprotocol.io/specification for newer revisions before starting.

## 1. Should this be an MCP server?

| Situation | Choose |
|---|---|
| Capability reused across several agents, hosts or teams; integration with auth that others will also need | MCP server |
| One agent, one codebase, tools only that agent uses | native tools in the harness (simpler, no protocol overhead); wrap in MCP later if reuse appears |
| A multi-step procedure over existing tools | a skill, possibly alongside an MCP server (MCP connects, skills teach the workflow) |
| A long, data-heavy chain of calls | expose the server's tools as code APIs in a sandbox (code execution with MCP) rather than direct tool calls |

## 2. Pick the right primitive

| Primitive | Controlled by | Use for |
|---|---|---|
| **Tools** | the model decides when to call | actions and queries the agent chooses: search, create, update, compute |
| **Resources** | the host/application decides what to include | readable context addressed by URI: files, records, schemas, docs; user pickers, @-mentions |
| **Prompts** | the user invokes explicitly | reusable templates surfaced as slash commands |

- Most agent value comes from tools; many hosts (including the Claude API connector) use only tools. Do not hide essential functionality in resources or prompts.
- **Server `instructions`** (returned from discovery) tell the model what the server is for and when to look for its tools. With tool search on by default in hosts like Claude Code, instructions are often the only thing loaded up front: state the domain, when to use the server, and key capabilities in the first few hundred characters. Do not repeat tool descriptions.
- **Client-side features**: elicitation (ask the user for structured input mid-call) is current. Sampling, roots and logging are **deprecated** in 2026-07-28: call your own LLM provider directly, take paths as tool parameters, log to stderr or OpenTelemetry.

## 3. Design the tools for agents

Everything in `agent-tool-design` applies. MCP-specific points:

- **Small, task-shaped surface.** Each server's tools sit in the context of every agent that connects it. One job per tool, reads separated from writes, split tools whose permission or risk differs. Deterministic `tools/list` order (helps prompt caching).
- **Names**: 1–128 characters, `A-Z a-z 0-9 _ - .`, unique per server, namespaced by service. Hosts prefix server names (Claude Code: `mcp__<server>__<tool>`; tools whose full name exceeds 128 characters are dropped), so keep them short.
- **Schemas**: `inputSchema` must be a valid JSON Schema object (2020-12 by default); use `{"type":"object","additionalProperties":false}` for no-arg tools. Make every required value explicit; never make the model guess IDs.
- **Structured output**: declare `outputSchema` when results are data; return conforming `structuredContent` **and** the same JSON as a text block for older clients. Return stable IDs the next call needs.
- **Errors**: protocol problems (unknown tool, malformed request) are JSON-RPC errors; business failures (validation, upstream API down, not found, expired handle) are results with `isError: true` and an actionable message so the model can self-correct.
- **Annotations** on every tool: `readOnlyHint`, `destructiveHint` (defaults to **true**), `idempotentHint`, `openWorldHint` (defaults to **true**). Set them honestly; hosts use them for permission prompts and parallelism. They are hints: never a substitute for server-side authorisation, and clients must treat them as untrusted.
- **State across calls** (2026-07-28 has no sessions): mint an opaque, high-entropy, expiring handle (`cart_id`), return it, accept it as an ordinary argument, re-check authorisation against it on every call, state its lifetime in the description, and return `isError` when it has expired. Possession of a handle is never authentication.
- **Large results**: paginate with opaque cursors; return resource links instead of inlining big payloads; hosts truncate or spill large results (limits per host in `references/clients-and-tooling.md`).
- **Long-running work**: return quickly with a job reference, or use the `io.modelcontextprotocol/tasks` extension (poll, cancel, mid-flight input) when the client declares it; send progress notifications if the client sent a progress token.
- **Interactive UI**: the MCP Apps extension (`io.modelcontextprotocol/ui`) lets a tool point to a sandboxed HTML resource the host renders. Always return a meaningful text result as well for hosts without UI support.

## 4. Choose the transport

| Transport | Use when | Must-dos |
|---|---|---|
| **stdio** | local, single-user server launched by the host | never write non-protocol output to stdout (logs to stderr; a stray `print()` corrupts the stream); exit when stdin closes; credentials from environment, not OAuth |
| **Streamable HTTP** | remote or shared server; required by the Claude API connector, OpenAI Responses API and ChatGPT apps | single HTTPS endpoint (usually `/mcp`); when an `Origin` header is present and not allowed, reject with 403 (DNS-rebinding defence; server-to-server callers often send none and rely on auth); bind local HTTP servers to 127.0.0.1 and require a token; authenticate every connection; disable proxy buffering for streamed responses |

HTTP+SSE (the 2024 transport) is deprecated; do not build new servers on it.

## 5. Authorise remote servers properly

For HTTP servers that act for a user, implement the spec's OAuth 2.1 profile; the MCP server is a **resource server**, ideally with a separate authorisation server (your IdP).

1. Publish **Protected Resource Metadata** (RFC 9728) at `/.well-known/oauth-protected-resource`, naming your authorisation server(s) and minimal `scopes_supported`.
2. On a missing/invalid token return **401** with `WWW-Authenticate: Bearer resource_metadata="…", scope="…"`. On insufficient scope return **403** `insufficient_scope` listing every scope the operation needs.
3. **Validate the token audience**: accept only tokens issued for this server's canonical URI (clients send it as the RFC 8707 `resource` parameter). Reject everything else with 401.
4. **Never pass the client's token through** to downstream APIs. To call a third-party API, the server is its own OAuth client: obtain the user's consent via URL-mode elicitation, store the third-party token server-side bound to the user, and never route it through the MCP client.
5. Client registration: the spec now prefers pre-registration or **Client ID Metadata Documents** and deprecates dynamic client registration, but hosts adopt spec changes at different speeds. Check which registration methods and protocol revisions each target host (Claude Code, Claude API, ChatGPT, IDEs) supports today and keep DCR enabled while a host you need still depends on it.
6. Least-privilege scopes with incremental step-up; no omnibus or wildcard scopes; log elevations.

**Calling your own backend (first-party API).** The MCP server usually fronts an existing API. Do not forward the MCP token to it. Either exchange it for a token whose audience is the backend (OAuth token exchange, RFC 8693, via your IdP), or call the backend with a service credential over a trusted internal channel and pass the user ID taken from the *validated* MCP token. Keep authorisation enforced in the backend too, not only in the MCP layer.

Machine-to-machine and enterprise SSO have their own auth extensions. Local stdio servers skip OAuth and read credentials from the environment (or the OS keychain via the packaging format).

## 6. Multi-user servers

- **Identity comes from the token, never from tool arguments.** No `user_id` parameter on "my data" tools; derive it from the validated token on every call.
- Enforce row-level access in the backend; return the same "not found" for missing and forbidden objects so IDs cannot be probed.
- Mark per-user list/read results `cacheScope: private` (2026-07-28) so shared caches never mix users.
- Test cross-tenant access for every tool (user A's token against user B's IDs) and wrong-audience / expired tokens in CI.
- Separate audiences with separate scopes (or separate servers): end users get user scopes; internal engineers and admin tools get distinct, elevated scopes that consumer hosts never request.
- Minimise sensitive fields in results (precise locations, contact details) to what the task needs.

## 7. Security checklist for the server

The protocol cannot make a server safe; these are the server's job.

- Validate every input; enforce access control per call; rate-limit; sanitise outputs; sanitise `file://` paths against traversal.
- Token passthrough forbidden; audience validated; tokens never in URLs, logs or tool results.
- **Confused deputy** (proxy servers fronting a third-party OAuth API with a static client ID): obtain per-client user consent before forwarding; exact `redirect_uri` match; single-use `state`; hardened consent cookies.
- Elicitation: never request passwords, API keys, tokens or payment data via form mode (use URL mode); never put PII or credentials in URLs; verify the user who completes a URL flow is the one who started it.
- Treat anything echoed back by the client (e.g. `requestState`) as attacker-controlled; integrity-protect it if it affects authorisation.
- Tool results that carry third-party content are injection vectors for the calling agent: label provenance and keep instructions out of results (`agent-security`).
- Keep descriptions stable and honest; changing behaviour after users approved it is exactly the "rug pull" pattern clients defend against.
- **Confirmations for destructive tools** happen in the host, so plan per host: annotations drive host prompts (Claude Code also honours `_meta` `anthropic/requiresUserInteraction`; OpenAI hosts use `require_approval`); MRTR elicitation can ask the user directly where the client declares it; hosts without either (the Claude API connector exposes tools only) need the confirmation in the calling application. For irreversible actions, consider a two-step tool pair (`*_prepare` returns a summary and a short-lived confirmation token, `*_commit` requires it).

**Using someone else's server** (client side): read every tool description in full (hidden instructions = tool poisoning); pin package versions or the tool list (the Claude API connector can pin a server's tool list); prefer servers run by the service provider over aggregators; restrict to an allowlist of tools; require approval for write tools; watch for one server's descriptions steering how another server's tools are used (cross-server shadowing); sandbox local servers with minimal privileges; never run one-click installs without reading the full command.

## 8. Build, test, ship

1. **Start from an official SDK** (Tier 1: TypeScript, Python, C#, Go, Rust, Ruby). Use the SDK's helpers that serve both protocol eras; hand-wired legacy transports only serve old clients. SDK APIs moved with the 2026-07-28 revision: follow the current quickstart for your language (HTTP serving, auth/token verification and dual-era support differ per SDK). Minimal servers in `references/clients-and-tooling.md`.
2. **Test with MCP Inspector** (`npx @modelcontextprotocol/inspector`): web UI for exploration, `--cli` for scripted checks in CI (list tools, call each with valid and invalid input, check `isError` paths, check both protocol eras).
3. **Test with a real agent**: connect it to Claude Code (`claude mcp add …`) and run realistic multi-step tasks; read transcripts for wrong-tool choices, guessed IDs and ignored errors. Then build the eval loop in `agent-tool-design` §9.
4. **Version**: add fields and tools rather than changing them; deprecate before removing; implement `server/discover` and return a supported-versions error for unknown protocol versions.
5. **Ship**: local servers as a package (npm/PyPI/container) or an MCPB bundle (one-click install, secrets in the OS keychain); remote servers on a stable HTTPS URL; publish metadata to the MCP Registry for public servers, or run a private registry. In a plugin, declare the server in the plugin's `.mcp.json` using `${CLAUDE_PLUGIN_ROOT}`.
6. **Observe**: log every call (tool, caller, scopes, latency, error, result size) without logging tokens or sensitive payloads; propagate the `traceparent` from `_meta` into your tracing (`llm-production-ops`).

## Anti-patterns

- One MCP tool per REST endpoint; dozens of tools per server
- Business errors thrown as protocol errors (the model never sees them)
- `print()` debugging in a stdio server
- Remote HTTP server without auth, or local HTTP bound to 0.0.0.0 without a token
- Forwarding the client's bearer token to downstream APIs; skipping audience checks
- Asking for secrets through form elicitation
- Treating annotations or handles as security controls
- Building on sampling, roots, logging or HTTP+SSE in a new server
- Installing third-party servers without reading their tool descriptions

## Checklist for a new or changed MCP server

- [ ] MCP is justified over native tools; server `instructions` state domain and when to use it
- [ ] Small tool set designed per `agent-tool-design`; names ≤128 chars, namespaced; strict schemas; `outputSchema` + `structuredContent` + text fallback where data is returned
- [ ] Business failures return `isError` with actionable messages
- [ ] Honest annotations on every tool; destructive tools also gated by the host's approval flow
- [ ] Cross-call state uses expiring handles re-authorised on every call
- [ ] Transport chosen; stdout clean (stdio) or Origin validated + localhost binding + auth (HTTP)
- [ ] Remote auth: PRM published, 401/403 challenges, audience validation, no token passthrough (token exchange or service credential to the backend), minimal scopes, registration methods match target hosts
- [ ] Identity from the token only; cross-tenant tests; private cache scope on per-user results
- [ ] Inputs validated, rate limits, path sanitisation, no secrets in results or logs
- [ ] Inspector CLI checks in CI for both protocol eras; real-agent transcripts reviewed; eval tasks exist
- [ ] Versioning and distribution path defined; calls logged and traced

See `references/protocol-2026-07-28.md` for what changed in the stateless revision, MRTR, elicitation, extensions and the full authorisation flow, and `references/clients-and-tooling.md` for SDK quickstarts (verify against the current SDK docs), Inspector commands, and connecting servers to Claude Code, the Claude API and OpenAI.

## Sources

- MCP specification (2026-07-28) and changelog: https://modelcontextprotocol.io/specification/2026-07-28/changelog
- Tools: https://modelcontextprotocol.io/specification/2026-07-28/server/tools
- Transports: https://modelcontextprotocol.io/specification/2026-07-28/basic/transports
- Authorization: https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization
- Security best practices: https://modelcontextprotocol.io/specification/2026-07-28/basic/security_best_practices
- Extensions (tasks, apps): https://modelcontextprotocol.io/extensions/overview
- Build a server quickstart: https://modelcontextprotocol.io/docs/2026-07-28/develop/build-server
- MCP Inspector: https://modelcontextprotocol.io/docs/tools/inspector
- Code execution with MCP: https://www.anthropic.com/engineering/code-execution-with-mcp
- Introducing advanced tool use (tool search): https://www.anthropic.com/engineering/advanced-tool-use
- Desktop extensions (MCPB): https://www.anthropic.com/engineering/desktop-extensions
- Claude Code MCP: https://code.claude.com/docs/en/mcp
- Claude API MCP connector: https://platform.claude.com/docs/en/agents-and-tools/mcp-connector
- OpenAI remote MCP (Responses API): https://developers.openai.com/api/docs/guides/tools-connectors-mcp
- OpenAI Apps SDK, planning tools: https://developers.openai.com/apps-sdk/plan/tools
- Tool poisoning disclosure (Invariant Labs, third party): https://invariantlabs.ai/blog/mcp-security-notification-tool-poisoning-attacks
