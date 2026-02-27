import Foundation

struct ToolSchemaEntry: Sendable {
    let name: String
    let description: String
    let properties: [String: [String: String]]
    let required: [String]
}

enum ToolSchemaCatalog {
    static let entries: [ToolSchemaEntry] = [
        ToolSchemaEntry(
            name: "read",
            description: "Read file content from the workspace",
            properties: [
                "path": ["type": "string", "description": "File path (absolute or workspace-relative)"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "glob",
            description: "Find files by glob-like pattern",
            properties: [
                "pattern": ["type": "string", "description": "Pattern to match, for example *.swift"],
                "path": ["type": "string", "description": "Optional base path scope"]
            ],
            required: ["pattern"]
        ),
        ToolSchemaEntry(
            name: "grep",
            description: "Search text in files",
            properties: [
                "query": ["type": "string", "description": "Text or regex query"],
                "pattern": ["type": "string", "description": "Alias for query"],
                "pathScope": ["type": "string", "description": "Optional folder or file scope"],
                "path": ["type": "string", "description": "Alias for pathScope"],
                "fileType": ["type": "string", "description": "Optional file type filter"],
                "context_lines": ["type": "string", "description": "Optional context lines"],
                "case_sensitive": ["type": "string", "description": "true or false"],
                "multiline": ["type": "string", "description": "true or false"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "edit",
            description: "Overwrite file with new content",
            properties: [
                "path": ["type": "string", "description": "Target file path"],
                "content": ["type": "string", "description": "Full file content to write"]
            ],
            required: ["path", "content"]
        ),
        ToolSchemaEntry(
            name: "write",
            description: "Alias of edit",
            properties: [
                "path": ["type": "string", "description": "Target file path"],
                "content": ["type": "string", "description": "Full file content to write"]
            ],
            required: ["path", "content"]
        ),
        ToolSchemaEntry(
            name: "str_replace",
            description: "Replace exact text in a file",
            properties: [
                "path": ["type": "string", "description": "Target file path"],
                "old_string": ["type": "string", "description": "Exact string to replace"],
                "new_string": ["type": "string", "description": "Replacement string"]
            ],
            required: ["path", "old_string", "new_string"]
        ),
        ToolSchemaEntry(
            name: "create_file",
            description: "Create a new file",
            properties: [
                "path": ["type": "string", "description": "Target file path"],
                "content": ["type": "string", "description": "Initial file content"]
            ],
            required: ["path", "content"]
        ),
        ToolSchemaEntry(
            name: "bash",
            description: "Run shell command in the workspace",
            properties: [
                "command": ["type": "string", "description": "Shell command"],
                "cwd": ["type": "string", "description": "Optional working directory"]
            ],
            required: ["command"]
        ),
        ToolSchemaEntry(
            name: "read_range",
            description: "Read a line range from a file",
            properties: [
                "path": ["type": "string", "description": "Target file path"],
                "start": ["type": "string", "description": "Start line (1-based)"],
                "end": ["type": "string", "description": "End line (inclusive)"],
                "start_line": ["type": "string", "description": "Alias for start"],
                "end_line": ["type": "string", "description": "Alias for end"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "list_dir",
            description: "List directory entries",
            properties: [
                "path": ["type": "string", "description": "Directory path"],
                "maxEntries": ["type": "string", "description": "Optional max number of entries"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "git_diff",
            description: "Show git diff",
            properties: [
                "path": ["type": "string", "description": "Optional path scope"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "search_symbols",
            description: "Search code symbols",
            properties: [
                "query": ["type": "string", "description": "Symbol query"],
                "kind": ["type": "string", "description": "class|struct|enum|protocol|function|all"]
            ],
            required: ["query"]
        ),
        ToolSchemaEntry(
            name: "run_tests",
            description: "Run project tests",
            properties: [
                "target": ["type": "string", "description": "Optional test target or filter"],
                "filter": ["type": "string", "description": "Optional test filter"],
                "timeout_ms": ["type": "string", "description": "Timeout in milliseconds"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "run_single_test",
            description: "Run a single test by name",
            properties: [
                "test_name": ["type": "string", "description": "Test name"],
                "file": ["type": "string", "description": "Optional file path"]
            ],
            required: ["test_name"]
        ),
        ToolSchemaEntry(
            name: "build_project",
            description: "Build the project",
            properties: [
                "configuration": ["type": "string", "description": "debug or release"],
                "target": ["type": "string", "description": "Optional build target"],
                "timeout_ms": ["type": "string", "description": "Timeout in milliseconds"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "diagnostics",
            description: "Get structured build diagnostics",
            properties: [
                "manager": ["type": "string", "description": "Optional build manager override"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "read_lints",
            description: "Read lints and diagnostics without full build",
            properties: [
                "path": ["type": "string", "description": "Optional file scope"],
                "severity": ["type": "string", "description": "all|error|warning"],
                "limit": ["type": "string", "description": "Maximum number of diagnostics"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "attempt_completion",
            description: "Signal task completion with optional verification",
            properties: [
                "result": ["type": "string", "description": "Completion summary"],
                "command": ["type": "string", "description": "Optional verification command"]
            ],
            required: ["result"]
        ),
        ToolSchemaEntry(
            name: "list_processes",
            description: "List running processes",
            properties: [
                "filter": ["type": "string", "description": "Optional process filter"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "read_json",
            description: "Read and pretty-print JSON file",
            properties: [
                "path": ["type": "string", "description": "JSON file path"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "write_json",
            description: "Merge JSON patch into JSON file",
            properties: [
                "path": ["type": "string", "description": "JSON file path"],
                "patch": ["type": "string", "description": "JSON object patch string"]
            ],
            required: ["path", "patch"]
        ),
        ToolSchemaEntry(
            name: "workspace_stats",
            description: "Collect workspace statistics",
            properties: [
                "path": ["type": "string", "description": "Optional relative scope"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "dependency_audit",
            description: "Run dependency audit",
            properties: [
                "manager": ["type": "string", "description": "swift|npm|pnpm|yarn"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "tail_log",
            description: "Tail a log file",
            properties: [
                "path": ["type": "string", "description": "Log file path"],
                "lines": ["type": "string", "description": "Number of lines"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "codebase_search",
            description: "Search codebase symbols with the structured index",
            properties: [
                "query": ["type": "string", "description": "Search query"],
                "kind": ["type": "string", "description": "Symbol kind filter"],
                "filePattern": ["type": "string", "description": "Optional file glob filter"],
                "path": ["type": "string", "description": "Alias for filePattern"]
            ],
            required: ["query"]
        ),
        ToolSchemaEntry(
            name: "find_symbol",
            description: "Find exact symbol definitions",
            properties: [
                "query": ["type": "string", "description": "Exact symbol name"],
                "name": ["type": "string", "description": "Alias for query"],
                "kind": ["type": "string", "description": "Optional symbol kind"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "list_symbols",
            description: "List symbols in a specific file",
            properties: [
                "path": ["type": "string", "description": "File path"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "find_references",
            description: "Find symbol references",
            properties: [
                "query": ["type": "string", "description": "Symbol name"],
                "name": ["type": "string", "description": "Alias for query"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "project_structure",
            description: "Show project file structure",
            properties: [
                "maxDepth": ["type": "string", "description": "Optional max depth"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "file_outline",
            description: "Show structured file outline",
            properties: [
                "path": ["type": "string", "description": "File path"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "find_files",
            description: "Find files by fuzzy name matching with optional scope filters",
            properties: [
                "query": ["type": "string", "description": "File name query"],
                "pattern": ["type": "string", "description": "Alias for query"],
                "path": ["type": "string", "description": "Alias for filePattern (directory scope)"],
                "filePattern": ["type": "string", "description": "Optional path/glob filter"],
                "extension": ["type": "string", "description": "Optional extension filter"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "codebase_stats",
            description: "Return codebase statistics",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "dependency_graph",
            description: "Show dependency graph for a file",
            properties: [
                "path": ["type": "string", "description": "File path"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "list_types",
            description: "List all types in the codebase",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "list_tests",
            description: "List all tests in the codebase",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "index_status",
            description: "Show index status and health",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "reindex",
            description: "Force codebase reindexing",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "semantic_search",
            description: "Search code by intent and meaning",
            properties: [
                "query": ["type": "string", "description": "Natural language query"],
                "target_directories": ["type": "string", "description": "Optional comma-separated directories"],
                "num_results": ["type": "string", "description": "Maximum results (1-50)"],
                "limit": ["type": "string", "description": "Alias for num_results"]
            ],
            required: ["query"]
        ),
        ToolSchemaEntry(
            name: "parallel_apply",
            description: "Apply multiple independent text edits in one call",
            properties: [
                "edits": ["type": "string", "description": "JSON array of edit objects"]
            ],
            required: ["edits"]
        ),
        ToolSchemaEntry(
            name: "regex_replace",
            description: "Run regex find and replace in a file",
            properties: [
                "path": ["type": "string", "description": "Target file path"],
                "pattern": ["type": "string", "description": "Regex pattern"],
                "replacement": ["type": "string", "description": "Replacement string"],
                "flags": ["type": "string", "description": "Optional regex flags"]
            ],
            required: ["path", "pattern", "replacement"]
        ),
        ToolSchemaEntry(
            name: "rename_symbol",
            description: "Rename a symbol across the codebase",
            properties: [
                "old_name": ["type": "string", "description": "Current symbol name"],
                "new_name": ["type": "string", "description": "New symbol name"],
                "kind": ["type": "string", "description": "Optional symbol kind"]
            ],
            required: ["old_name", "new_name"]
        ),
        ToolSchemaEntry(
            name: "find_and_replace_all",
            description: "Run workspace-wide find and replace",
            properties: [
                "search": ["type": "string", "description": "Search text or regex"],
                "replacement": ["type": "string", "description": "Replacement text"],
                "filePattern": ["type": "string", "description": "Optional file glob"],
                "is_regex": ["type": "string", "description": "true or false"]
            ],
            required: ["search", "replacement"]
        ),
        ToolSchemaEntry(
            name: "undo_edit",
            description: "Revert a file to last committed state",
            properties: [
                "path": ["type": "string", "description": "Target file path"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "debug_context",
            description: "Gather debugging context",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "debug_log",
            description: "Write an entry to debug log",
            properties: [
                "severity": ["type": "string", "description": "error|warning|info|verbose|trace"],
                "source": ["type": "string", "description": "Source component or file"],
                "message": ["type": "string", "description": "Log message"],
                "detail": ["type": "string", "description": "Optional detail"],
                "category": ["type": "string", "description": "Optional category"]
            ],
            required: ["severity", "source", "message"]
        ),
        ToolSchemaEntry(
            name: "debug_query",
            description: "Query debug logs",
            properties: [
                "severity": ["type": "string", "description": "Optional severity filter"],
                "category": ["type": "string", "description": "Optional category filter"],
                "source": ["type": "string", "description": "Optional source filter"],
                "search": ["type": "string", "description": "Optional search query"],
                "format": ["type": "string", "description": "summary|full"],
                "limit": ["type": "string", "description": "Maximum number of rows"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "debug_session",
            description: "Manage debug sessions",
            properties: [
                "action": ["type": "string", "description": "start|end|clear"]
            ],
            required: ["action"]
        ),
        ToolSchemaEntry(
            name: "debug_hypothesize",
            description: "Propose or update debug hypothesis (ID-based contract)",
            properties: [
                "action": ["type": "string", "description": "propose|update"],
                "hypothesis_id": ["type": "string", "description": "Required for update; returned by propose"],
                "title": ["type": "string", "description": "Required for propose"],
                "description": ["type": "string", "description": "Optional hypothesis description"],
                "status": ["type": "string", "description": "proposed|investigating|confirmed|rejected"],
                "evidence": ["type": "string", "description": "Optional evidence notes"]
            ],
            required: ["action"]
        ),
        ToolSchemaEntry(
            name: "debug_mark",
            description: "Insert a debug marker into a file",
            properties: [
                "path": ["type": "string", "description": "File path"],
                "line": ["type": "string", "description": "Line number"],
                "comment": ["type": "string", "description": "Marker comment"],
                "code": ["type": "string", "description": "Optional marker code"]
            ],
            required: ["path", "line", "comment"]
        ),
        ToolSchemaEntry(
            name: "debug_clean",
            description: "Remove debug markers",
            properties: [
                "path": ["type": "string", "description": "Optional file scope"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "mcp",
            description: "Invoke MCP tool",
            properties: [
                "tool": ["type": "string", "description": "MCP tool name"],
                "args": ["type": "string", "description": "JSON string arguments"]
            ],
            required: ["tool"]
        ),
        ToolSchemaEntry(
            name: "mcp_call",
            description: "Invoke MCP tool",
            properties: [
                "tool": ["type": "string", "description": "MCP tool name"],
                "args": ["type": "string", "description": "JSON string arguments"]
            ],
            required: ["tool"]
        ),
        ToolSchemaEntry(
            name: "mcp_list_servers",
            description: "List configured MCP servers",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "mcp_list_tools",
            description: "List MCP tools",
            properties: [
                "server": ["type": "string", "description": "Optional server identifier"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "mcp_describe_tool",
            description: "Describe MCP tool schema",
            properties: [
                "server": ["type": "string", "description": "Optional server identifier"],
                "tool": ["type": "string", "description": "Tool name"]
            ],
            required: ["tool"]
        ),
        ToolSchemaEntry(
            name: "mcp_health",
            description: "Check MCP server health",
            properties: [
                "server": ["type": "string", "description": "Optional server identifier"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "mcp_reconnect",
            description: "Reconnect MCP server",
            properties: [
                "server": ["type": "string", "description": "Server identifier"]
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
        )
    ]

    static var openAIFunctionTools: [[String: Any]] {
        entries.map { entry in
            [
                "type": "function",
                "function": [
                    "name": entry.name,
                    "description": entry.description,
                    "parameters": [
                        "type": "object",
                        "properties": entry.properties,
                        "required": entry.required
                    ]
                ]
            ]
        }
    }

    static var anthropicTools: [[String: Any]] {
        entries.map { entry in
            [
                "name": entry.name,
                "description": entry.description,
                "input_schema": [
                    "type": "object",
                    "properties": entry.properties,
                    "required": entry.required
                ]
            ]
        }
    }
}
