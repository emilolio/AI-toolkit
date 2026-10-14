# MCP clients and tooling

SDK quickstarts, testing, and how to connect a server to Claude and OpenAI hosts. Checked October 2026; SDK APIs moved with the 2026-07-28 revision, so confirm against the current quickstart before copying.

## Minimal servers

**Python** (`uv add "mcp[cli]"`; the quickstart now uses `MCPServer`, which replaces `FastMCP`):

```python
import logging
from mcp.server import MCPServer

logging.basicConfig(level=logging.INFO)  # logs go to stderr; never print() in a stdio server
mcp = MCPServer("orders")

@mcp.tool()
async def orders_search(customer_email: str, status: str = "open", limit: int = 10) -> dict:
    """Search a customer's orders by email. Use this before orders_get when you only
    know the customer, not the order ID. Returns order IDs, dates, totals and status;
    at most `limit` results (max 50). Does not return line items (use orders_get)."""
    ...

if __name__ == "__main__":
    mcp.run(transport="stdio")
```

**TypeScript** (`npm install @modelcontextprotocol/server zod`):

```ts
import { McpServer, serveStdio } from "@modelcontextprotocol/server";
import { z } from "zod";

function createServer() {
  const server = new McpServer({ name: "orders", version: "1.0.0" });
  server.registerTool(
    "orders_search",
    {
      description: "Search a customer's orders by email. …",
      inputSchema: z.object({ customer_email: z.string().email(), limit: z.number().int().max(50).default(10) }),
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ customer_email, limit }) => ({ content: [{ type: "text", text: "…" }] }),
  );
  return server;
}

serveStdio(createServer); // factory: fresh server per call; serves 2026-07-28 and legacy clients
```

Hand-wiring `server.connect(new StdioServerTransport())` serves only legacy (2025-era) clients.

## MCP Inspector

```bash
npx @modelcontextprotocol/inspector node build/index.js                 # web UI
npx @modelcontextprotocol/inspector --cli node build/index.js --method tools/list
npx @modelcontextprotocol/inspector --cli node build/index.js --protocol-era modern --method tools/list
npx @modelcontextprotocol/inspector --server-url https://mcp.example.com/mcp --transport http
```

Requires Node ≥ 22.19. Use `--cli` in CI: list tools, call each with valid and invalid arguments, assert `isError` paths. Without an OS keychain, Inspector stores secrets unencrypted in `~/.mcp-inspector/`.

## Claude Code

```bash
claude mcp add --transport http orders https://mcp.example.com/mcp
claude mcp add --transport stdio --env ORDERS_API_URL=http://localhost:8080 orders -- node build/index.js
claude mcp list
claude mcp login orders            # OAuth sign-in (or /mcp in a session)
```

- Scopes: `local` (default, this project, `~/.claude.json`), `project` (checked-in `.mcp.json`, requires approval), `user` (all projects). Precedence: local > project > user > plugin > claude.ai connectors.
- `.mcp.json` supports `${VAR}` and `${VAR:-default}`. Plugins declare servers in their `.mcp.json` / `plugin.json` with `${CLAUDE_PLUGIN_ROOT}`.
- Tool search is on by default: only tool names and server `instructions` load up front. Instructions and up-front descriptions are truncated at 4,096 characters, searched descriptions at 16,384: put keywords first.
- Output limits: warning at 10k tokens, `MAX_MCP_OUTPUT_TOKENS` default 25k; results over 50,000 characters are written to a file.
- Vendor `_meta` on tools: `anthropic/requiresUserInteraction` (always prompt), `anthropic/maxResultSizeChars` (raise the spill threshold), `anthropic/alwaysLoad` (exempt from tool-search deferral).
- Prompts appear as `/mcp__<server>__<prompt>`; resources via `@` mentions; `list_changed` refreshes tools without reconnecting.

## Claude API MCP connector

Remote (public HTTPS) servers only; tools only (no resources/prompts); not eligible for zero data retention; your code runs OAuth and passes the token.

```json
{
  "mcp_servers": [
    { "type": "url", "url": "https://mcp.example.com/mcp", "name": "orders", "authorization_token": "…" }
  ],
  "tools": [
    { "type": "mcp_toolset", "mcp_server_name": "orders",
      "default_config": { "enabled": true, "defer_loading": true },
      "configs": { "orders_search": { "defer_loading": false } } }
  ]
}
```

Requires an MCP client beta header (check the docs for the current value; a newer beta adds tool-list pinning so a server cannot change its tools mid-conversation). Results arrive as `mcp_tool_use` / `mcp_tool_result` blocks. For stdio servers, resources or prompts, use the SDK's client-side MCP helpers instead.

## OpenAI

**Responses API remote MCP tool**

```json
{ "type": "mcp", "server_label": "orders", "server_url": "https://mcp.example.com/mcp",
  "allowed_tools": ["orders_search"], "require_approval": "always", "authorization": "…" }
```

Approval is required by default (`mcp_approval_request` → `mcp_approval_response`); `authorization` is not stored, so send it on every request; the tool list is cached while it stays in context. OpenAI warns that servers can change tool behaviour without notice: log what is sent, prefer provider-run servers, and do not follow URLs from tool output.

**Agents SDK**: `MCPServerStdio`, `MCPServerStreamableHttp` (`MCPServerSse` legacy), `HostedMCPTool`; `create_static_tool_filter`, `cache_tools_list=True` with `invalidate_tools_cache()`, `require_approval` (always / never / per-tool map / callable).

**Apps SDK (ChatGPT apps)**: public HTTPS Streamable HTTP endpoint; private servers behind OpenAI-managed mTLS plus OAuth 2.1 (IP allowlists are not authentication). Guidance: one job per tool, reads separated from writes, key server instructions in the first 512 characters, stable IDs in `structuredContent`, `_meta` for client-only data (not a security boundary), backward-compatible schema changes.

## Packaging and distribution

- **MCPB** (formerly DXT): a `.mcpb` zip with `manifest.json` (`server.type` node/python/binary, `entry_point`, `mcp_config`, `user_config`, `tools`, `prompts`, `compatibility`). `"sensitive": true` user-config values are stored in the OS keychain and injected via `${user_config.key}`. `npx @anthropic-ai/mcpb init`, `mcpb pack`.
- **MCP Registry** (preview): metadata only (`server.json`) pointing to packages on npm/PyPI/containers; reverse-DNS names verified via GitHub, DNS or HTTP; public servers only; run a private registry for internal servers.

## Measured effects worth knowing

- Code execution over MCP tools: one workflow ~150k → ~2k tokens (Anthropic).
- Tool search with deferred loading: 58 tools across 5 servers ~55k → ~8.7k tokens of definitions, and higher MCP eval accuracy (e.g. 49% → 74% on one model) (Anthropic).
- Tool use examples: parameter accuracy 72% → 90% (Anthropic).

## Sources

- https://modelcontextprotocol.io/docs/2026-07-28/develop/build-server
- https://modelcontextprotocol.io/docs/sdk
- https://modelcontextprotocol.io/docs/tools/inspector
- https://modelcontextprotocol.io/registry/about
- https://code.claude.com/docs/en/mcp
- https://platform.claude.com/docs/en/agents-and-tools/mcp-connector
- https://www.anthropic.com/engineering/desktop-extensions
- https://www.anthropic.com/engineering/code-execution-with-mcp
- https://www.anthropic.com/engineering/advanced-tool-use
- https://developers.openai.com/api/docs/guides/tools-connectors-mcp
- https://openai.github.io/openai-agents-python/mcp/
- https://developers.openai.com/apps-sdk/build/mcp-server
- https://developers.openai.com/apps-sdk/plan/tools
