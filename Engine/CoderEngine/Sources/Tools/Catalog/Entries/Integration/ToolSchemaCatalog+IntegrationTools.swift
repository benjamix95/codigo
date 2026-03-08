import Foundation

extension ToolSchemaCatalog {
    static let integrationTools: [ToolSchemaEntry] = [
        ToolSchemaEntry(
            name: "skill",
            description: "Invoke a local skill (SKILL.md) from ~/.codex/skills, ~/.claude/skills, or ~/.agents/skills. Use when task matches a skill (doc, imagegen, transcribe, playwright, cloudflare-deploy, gh-fix-ci). Prefer skills over manual workflows.",
            properties: [
                "skill": ["type": "string", "description": "Skill name (e.g. doc, imagegen, transcribe)"],
                "name": ["type": "string", "description": "Alias for skill"],
                "task": ["type": "string", "description": "What the skill should do"],
                "args": ["type": "string", "description": "Alias for task"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "multi_edit",
            description: "Apply multiple edits to a single file atomically. All edits are validated before any are applied. Each edit uses the same old_string/new_string matching as str_replace. If any edit fails validation (not found, not unique), no changes are made.",
            properties: [
                "path": ["type": "string", "description": "File path (absolute or workspace-relative)"],
                "edits": ["type": "string", "description": "JSON array of edit objects: [{\"old_string\": \"...\", \"new_string\": \"...\"}]. Each old_string must be unique in the file."]
            ],
            required: ["path", "edits"]
        ),
        ToolSchemaEntry(
            name: "related_files",
            description: "Find files related to a given file: tests, imports, dependents, similarly-named files, and sibling files. Useful for understanding a file's context before editing.",
            properties: [
                "path": ["type": "string", "description": "File path to find related files for"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "git_log_search",
            description: "Search git history for commits that introduced or removed specific code patterns (git pickaxe -S). Also searches commit messages. Useful for finding when code was added/changed and by whom.",
            properties: [
                "query": ["type": "string", "description": "Code pattern or text to search for in git history"],
                "path": ["type": "string", "description": "Optional: limit search to a specific file or directory"],
                "author": ["type": "string", "description": "Optional: filter by commit author name"],
                "since": ["type": "string", "description": "Optional: search commits after this date (e.g., '2024-01-01', '3 months ago')"],
                "limit": ["type": "string", "description": "Maximum commits to return (default: 20, max: 50)"]
            ],
            required: ["query"]
        ),

        // ── Power tools ──────────────────────────────────────────────────────

        ToolSchemaEntry(
            name: "apply_diff",
            description: "Apply a unified diff patch to a file. Accepts standard unified diff format with @@ hunk headers. Use this for complex multi-line changes where str_replace would be cumbersome.",
            properties: [
                "path": ["type": "string", "description": "File path to apply the diff to"],
                "diff": ["type": "string", "description": "Unified diff string with @@ hunk headers. Lines starting with '-' are removed, '+' are added, ' ' (space) are context."]
            ],
            required: ["path", "diff"]
        ),
        ToolSchemaEntry(
            name: "batch_read",
            description: "Read multiple files in a single call to reduce round-trips. Returns numbered line content for each file. Max 20 files per call.",
            properties: [
                "paths": ["type": "string", "description": "JSON array of file paths, or comma-separated list of paths (e.g. [\"src/a.ts\", \"src/b.ts\"] or \"src/a.ts, src/b.ts\")"]
            ],
            required: ["paths"]
        ),
        ToolSchemaEntry(
            name: "diff_files",
            description: "Compare two files and show their differences in unified diff format. Useful for understanding what changed between two versions of a file.",
            properties: [
                "file1": ["type": "string", "description": "Path to the first file (base)"],
                "file2": ["type": "string", "description": "Path to the second file (comparison)"],
                "context": ["type": "string", "description": "Number of context lines around changes (default: 3, max: 10)"]
            ],
            required: ["file1", "file2"]
        ),
        ToolSchemaEntry(
            name: "git_status",
            description: "Show structured git status: current branch, tracking info (ahead/behind), staged changes, unstaged changes, untracked files, and merge conflicts. No arguments needed.",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "git_show",
            description: "Show details of a specific git commit: author, date, message, stats, and full diff. Defaults to HEAD if no commit is specified.",
            properties: [
                "commit": ["type": "string", "description": "Git commit ref — hash, branch, tag, HEAD~N, etc. (default: HEAD)"],
                "stat_only": ["type": "string", "description": "Set to 'true' to show only file stats without full diff"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "code_context",
            description: "Get full context around a symbol: definition source code, all references across the codebase, and file imports/dependencies. More comprehensive than grep for understanding code.",
            properties: [
                "symbol": ["type": "string", "description": "Symbol name to look up (function, class, struct, protocol, etc.)"],
                "max_refs": ["type": "string", "description": "Maximum references to return (default: 15, max: 30)"]
            ],
            required: ["symbol"]
        ),
        ToolSchemaEntry(
            name: "mcp_call",
            description: "Call an MCP tool on a connected MCP server. Pass arguments as top-level key-value pairs alongside 'tool' and 'server'. Only use this for tools NOT registered as native functions. For complex values (arrays, objects), pass them as JSON strings.",
            properties: [
                "server": ["type": "string", "description": "MCP server identifier (from mcp_list_servers). Required when tool name is ambiguous across servers."],
                "tool": ["type": "string", "description": "MCP tool name. Can use 'server/tool' format to specify both."],
                "args": ["type": "string", "description": "JSON object of tool arguments. Prefer passing args as top-level keys instead."]
            ],
            required: ["tool"]
        ),
        ToolSchemaEntry(
            name: "mcp_list_servers",
            description: "List all configured and connected MCP servers with their IDs and names.",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "mcp_list_tools",
            description: "List all available tools from MCP servers. Returns tool names, descriptions, and which server they belong to.",
            properties: [
                "server": ["type": "string", "description": "Filter by server identifier. If omitted, lists tools from all servers."]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "mcp_describe_tool",
            description: "Get the full JSON Schema for an MCP tool, including all parameters, types, and descriptions.",
            properties: [
                "server": ["type": "string", "description": "Server identifier to scope the search."],
                "tool": ["type": "string", "description": "Tool name to describe."]
            ],
            required: ["tool"]
        ),
        ToolSchemaEntry(
            name: "mcp_health",
            description: "Check health and detailed metrics of MCP servers. Returns status, uptime, call counts, latency stats (avg/p95), capabilities (tools/resources/prompts/logging), and error history for each server.",
            properties: [
                "server": ["type": "string", "description": "Check specific server. If omitted, checks all servers."]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "mcp_reconnect",
            description: "Force reconnect to an MCP server. Use when a server connection is broken or stale.",
            properties: [
                "server": ["type": "string", "description": "Server identifier to reconnect."]
            ],
            required: ["server"]
        ),

        // MARK: MCP Advanced Tools
        ToolSchemaEntry(
            name: "mcp_batch",
            description: "Execute multiple MCP tool calls in parallel. Accepts a JSON array of calls and returns all results. Much faster than sequential mcp_call for independent operations.",
            properties: [
                "calls": ["type": "string", "description": "JSON array of call objects: [{\"server\": \"...\", \"tool\": \"...\", \"args\": {...}}, ...]. Each call runs in parallel."],
                "timeout_ms": ["type": "string", "description": "Per-call timeout in milliseconds (default: 30000)"]
            ],
            required: ["calls"]
        ),
        ToolSchemaEntry(
            name: "mcp_list_resources",
            description: "List all resources exposed by MCP servers. Resources provide contextual data like files, database schemas, API specs, and application state.",
            properties: [
                "server": ["type": "string", "description": "Filter by server identifier. If omitted, lists resources from all servers."]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "mcp_read_resource",
            description: "Read the content of an MCP resource by URI. Returns text or binary (base64) content. Use mcp_list_resources first to discover available URIs.",
            properties: [
                "uri": ["type": "string", "description": "Resource URI to read (e.g. 'file:///path', 'db://schema', 'api://endpoint')"],
                "server": ["type": "string", "description": "Server identifier. Required if URI exists on multiple servers."]
            ],
            required: ["uri"]
        ),
        ToolSchemaEntry(
            name: "mcp_subscribe",
            description: "Subscribe to changes on an MCP resource. When the resource changes, the system receives a notification. Use 'unsubscribe' action to stop watching.",
            properties: [
                "uri": ["type": "string", "description": "Resource URI to watch for changes"],
                "server": ["type": "string", "description": "Server identifier"],
                "action": ["type": "string", "description": "'subscribe' (default) or 'unsubscribe'"]
            ],
            required: ["uri", "server"]
        ),
        ToolSchemaEntry(
            name: "mcp_list_prompts",
            description: "List prompt templates exposed by MCP servers. Prompts are reusable message templates with arguments for interacting with LLMs.",
            properties: [
                "server": ["type": "string", "description": "Filter by server identifier. If omitted, lists prompts from all servers."]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "mcp_get_prompt",
            description: "Resolve an MCP prompt template with arguments. Returns the generated messages ready to use. Use mcp_list_prompts first to discover available prompts and their arguments.",
            properties: [
                "name": ["type": "string", "description": "Prompt template name"],
                "server": ["type": "string", "description": "Server identifier. Required if prompt name exists on multiple servers."],
                "args": ["type": "string", "description": "JSON object of prompt arguments (supports strings, numbers, booleans, arrays, objects), e.g. {\"language\":\"python\",\"retries\":2,\"strict\":true}"]
            ],
            required: ["name"]
        ),
        ToolSchemaEntry(
            name: "mcp_logs",
            description: "Read structured logs from MCP servers. Filter by severity and server. Also supports setting the log level on a server.",
            properties: [
                "server": ["type": "string", "description": "Filter by server identifier. If omitted, shows logs from all servers."],
                "severity": ["type": "string", "description": "Minimum severity: debug, info, notice, warning, error, critical (default: info)"],
                "limit": ["type": "string", "description": "Maximum number of log entries to return (default: 50)"],
                "action": ["type": "string", "description": "'read' (default) to read logs, 'set_level' to change server log level, 'clear' to clear log buffer"],
                "level": ["type": "string", "description": "Log level to set when action is 'set_level'"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "mcp_restart_server",
            description: "Fully restart an MCP server process. Kills the process, resets the session, and reconnects. More aggressive than mcp_reconnect — use when reconnect fails or the server is in a bad state.",
            properties: [
                "server": ["type": "string", "description": "Server identifier to restart"]
            ],
            required: ["server"]
        ),
        ToolSchemaEntry(
            name: "web_search",
            description: "Search the web for current information",
            properties: [
                "query": ["type": "string", "description": "Search query terms"],
                "explanation": ["type": "string", "description": "Optional context for the search"]
            ],
            required: ["query"]
        ),
        ToolSchemaEntry(
            name: "web_fetch",
            description: "Fetch a web page and return clean markdown content",
            properties: [
                "url": ["type": "string", "description": "HTTP(S) URL to fetch"]
            ],
            required: ["url"]
        ),

        // MARK: Browser Tools
        ToolSchemaEntry(
            name: "browser_navigate",
            description: "Navigate the integrated browser to a URL. Opens the browser panel if not already visible.",
            properties: [
                "url": ["type": "string", "description": "Public HTTP(S) URL to navigate to"]
            ],
            required: ["url"]
        ),
        ToolSchemaEntry(
            name: "browser_screenshot",
            description: "Take a screenshot of the current browser page. Returns a base64-encoded PNG image.",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "browser_console_logs",
            description: "Read console logs from the integrated browser. Returns recent console output including errors, warnings, and info messages.",
            properties: [
                "level": ["type": "string", "description": "Filter by log level", "enum": "log,info,warn,error,debug"],
                "last_n": ["type": "string", "description": "Number of recent log entries to return (default: 100)"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "browser_click",
            description: "Click an element in the browser page using a CSS selector.",
            properties: [
                "selector": ["type": "string", "description": "CSS selector of the element to click (e.g. '#submit-btn', '.nav-link')"]
            ],
            required: ["selector"]
        ),
        ToolSchemaEntry(
            name: "browser_type",
            description: "Type text into an input field in the browser page.",
            properties: [
                "selector": ["type": "string", "description": "CSS selector of the input element"],
                "text": ["type": "string", "description": "Text to type into the field"]
            ],
            required: ["selector", "text"]
        ),
        ToolSchemaEntry(
            name: "browser_evaluate_js",
            description: "Execute arbitrary JavaScript in the browser page and return the result.",
            properties: [
                "script": ["type": "string", "description": "JavaScript code to execute in the page context"]
            ],
            required: ["script"]
        ),
        ToolSchemaEntry(
            name: "browser_get_content",
            description: "Get the full HTML content of the current browser page.",
            properties: [:],
            required: []
        )
    ]
}
