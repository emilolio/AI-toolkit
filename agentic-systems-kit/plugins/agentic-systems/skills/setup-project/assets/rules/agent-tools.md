# Tool design conventions

Applies whenever a tool, tool schema, MCP server or tool result format is created or changed. For the reasoning and the full checklist, load the `agent-tool-design` skill.

- A tool is a contract with a non-deterministic caller. Design it around the task the agent needs to finish, never as a one-to-one wrapper of an API endpoint.
- Keep the tool set small and non-overlapping. If a human engineer could not say which of two tools to pick, merge them or sharpen their boundaries.
- Related tools share a service prefix (`calendar_*`, `github_*`) and the project uses one word order consistently (e.g. `<service>_<action>_<resource>`: `calendar_find_slots`, `github_list_prs`). Test the scheme on the evals.
- Parameter names are unambiguous and typed: `user_id` not `user`; ISO 8601 for timestamps; enums for fixed choices. Use strict schemas (`additionalProperties: false`, explicit `required`).
- Descriptions are written as for a new hire (typically 3–6 sentences) and cover: what it does, when to use it, when NOT to use it (and which tool to use instead), what each parameter means, what it returns. Make implicit knowledge explicit (query syntax, domain terms, how resources relate).
- Results are high-signal and token-efficient: return names, titles, URLs and the identifiers needed for the next call; drop UUIDs, MIME types, pixel sizes and other metadata the agent cannot act on. Paginate, filter and truncate by default, and when truncating tell the agent how to narrow the query.
- Offer a `response_format` enum (`concise` | `detailed`) on tools whose output can be large.
- Do work inside the tool (filter, join, aggregate, summarise) rather than returning raw dumps for the agent to sift.
- Errors are actionable: say what failed, why, and what a valid call looks like. Never return opaque codes or stack traces. Flag the result as an error so the harness and the model can tell it apart from data.
- Do not ask the model for its reasoning as a tool parameter (the API may refuse it); ask for an explanation of the choice instead.
- Mark destructive or irreversible tools explicitly (annotations, naming, and a confirmation step in the harness).
- Every new or changed tool ships with at least one realistic multi-step eval task and one `input_example` if correct usage is not obvious from the schema.
