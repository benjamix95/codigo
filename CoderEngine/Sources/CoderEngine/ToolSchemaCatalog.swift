import Foundation

struct ToolSchemaEntry: Sendable {
    let name: String
    let description: String
    let properties: [String: [String: String]]
    let required: [String]
}

/// Stores native MCP tool definitions alongside the routing table.
/// Thread-safe via NSLock for concurrent access from providers + runtime.
final class MCPNativeToolRegistry: @unchecked Sendable {
    static let shared = MCPNativeToolRegistry()

    private let lock = NSLock()
    private var _entries: [ToolSchemaEntry] = []
    private var _routing: [String: (serverId: String, toolName: String)] = [:]
    private var _rawSchemas: [String: [String: Any]] = [:]

    var entries: [ToolSchemaEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    var routing: [String: (serverId: String, toolName: String)] {
        lock.lock()
        defer { lock.unlock() }
        return _routing
    }

    /// Full JSON Schema dict for a native MCP tool, used in OpenAI/Anthropic function params.
    func rawSchema(for functionName: String) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return _rawSchemas[functionName]
    }

    func hasTools() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !_entries.isEmpty
    }

    /// Register MCP tools as native function tools.
    /// Creates normalized function names and routing entries.
    func register(tools: [MCPToolDescriptor]) {
        lock.lock()
        defer { lock.unlock() }

        _entries.removeAll()
        _routing.removeAll()
        _rawSchemas.removeAll()

        var nameCount: [String: Int] = [:]
        for tool in tools {
            nameCount[tool.name, default: 0] += 1
        }

        for tool in tools {
            let needsPrefix = nameCount[tool.name, default: 0] > 1
            let functionName = Self.normalizeFunctionName(
                serverName: tool.serverName,
                toolName: tool.name,
                needsPrefix: needsPrefix
            )

            let simplifiedProps = Self.extractSimplifiedProperties(from: tool)

            _entries.append(ToolSchemaEntry(
                name: functionName,
                description: "[\(tool.serverName)] \(tool.description)",
                properties: simplifiedProps.properties,
                required: simplifiedProps.required
            ))

            _routing[functionName] = (serverId: tool.serverId, toolName: tool.name)

            if let schemaDict = tool.inputSchemaDict {
                _rawSchemas[functionName] = schemaDict
            }
        }
    }

    /// Normalize server/tool names into a valid OpenAI function name.
    /// Format: `toolname` if unique, `servername_toolname` if ambiguous.
    /// Must match `^[a-zA-Z0-9_-]{1,64}$`.
    private static func normalizeFunctionName(serverName: String, toolName: String, needsPrefix: Bool) -> String {
        let normalizedServer = serverName
            .replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        let normalizedTool = toolName
            .replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))

        let raw = needsPrefix ? "\(normalizedServer)_\(normalizedTool)" : normalizedTool
        let clamped = String(raw.prefix(64))
        return clamped.isEmpty ? "mcp_tool" : clamped
    }

    /// Extract simplified properties from an MCP tool descriptor.
    /// Flattens complex JSON Schema into [String: [String: String]] for ToolSchemaEntry.
    private static func extractSimplifiedProperties(from tool: MCPToolDescriptor) -> (properties: [String: [String: String]], required: [String]) {
        guard let schema = tool.inputSchemaDict,
              let props = schema["properties"] as? [String: Any] else {
            return (properties: [:], required: [])
        }

        var simplified: [String: [String: String]] = [:]
        for (key, value) in props {
            if let propDict = value as? [String: Any] {
                var entry: [String: String] = [:]
                if let type = propDict["type"] as? String {
                    entry["type"] = type
                } else {
                    entry["type"] = "string"
                }
                if let desc = propDict["description"] as? String {
                    entry["description"] = desc
                }
                if let enumValues = propDict["enum"] as? [String] {
                    entry["enum"] = enumValues.joined(separator: ", ")
                }
                simplified[key] = entry
            } else {
                simplified[key] = ["type": "string"]
            }
        }

        let required = (schema["required"] as? [String]) ?? []
        return (properties: simplified, required: required)
    }
}

enum ToolSchemaCatalog {
    /// Core built-in tool entries (static).
    static let coreEntries: [ToolSchemaEntry] = [
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
            name: "debug_set_phase",
            description: "Set the current debug flow phase in the IDE panel",
            properties: [
                "phase": ["type": "string", "description": "describing|reproducing|fixing|instrumenting|verifying|resolved"],
                "detail": ["type": "string", "description": "Optional detail about the phase transition"]
            ],
            required: ["phase"]
        ),
        ToolSchemaEntry(
            name: "debug_request_user",
            description: "Request user input or bug reproduction during debug",
            properties: [
                "kind": ["type": "string", "description": "question|reproduce"],
                "prompt": ["type": "string", "description": "The question or reproduction instructions for the user"]
            ],
            required: ["kind", "prompt"]
        ),
        ToolSchemaEntry(
            name: "debug_resolve",
            description: "Resolve the debug session with a final summary",
            properties: [
                "summary": ["type": "string", "description": "Summary of the root cause, fix applied, and verification outcome"]
            ],
            required: ["summary"]
        ),
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
            description: "Check health status of MCP servers. Returns 'ok' or error details for each server.",
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

    /// All tool entries: core built-in tools + registered native MCP tools.
    static var entries: [ToolSchemaEntry] {
        coreEntries + MCPNativeToolRegistry.shared.entries
    }

    static var openAIFunctionTools: [[String: Any]] {
        let core = coreEntries.map { formatOpenAI($0) }
        let mcpNative = MCPNativeToolRegistry.shared.entries.map { entry -> [String: Any] in
            if let rawSchema = MCPNativeToolRegistry.shared.rawSchema(for: entry.name) {
                return [
                    "type": "function",
                    "function": [
                        "name": entry.name,
                        "description": entry.description,
                        "parameters": rawSchema
                    ] as [String: Any]
                ]
            }
            return formatOpenAI(entry)
        }
        return core + mcpNative
    }

    static var anthropicTools: [[String: Any]] {
        let core = coreEntries.map { formatAnthropic($0) }
        let mcpNative = MCPNativeToolRegistry.shared.entries.map { entry -> [String: Any] in
            if let rawSchema = MCPNativeToolRegistry.shared.rawSchema(for: entry.name) {
                return [
                    "name": entry.name,
                    "description": entry.description,
                    "input_schema": rawSchema
                ] as [String: Any]
            }
            return formatAnthropic(entry)
        }
        return core + mcpNative
    }

    private static func formatOpenAI(_ entry: ToolSchemaEntry) -> [String: Any] {
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
            ] as [String: Any]
        ]
    }

    private static func formatAnthropic(_ entry: ToolSchemaEntry) -> [String: Any] {
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
