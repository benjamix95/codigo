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
            description: "Search text/regex in files using ripgrep. Supports output modes: 'content' (default, shows matching lines with context), 'files_only' (just file paths), 'count' (match counts per file). Supports glob filtering.",
            properties: [
                "query": ["type": "string", "description": "Text or regex pattern to search for"],
                "pattern": ["type": "string", "description": "Alias for query"],
                "pathScope": ["type": "string", "description": "Directory or file path to scope the search (comma-separated for multiple)"],
                "path": ["type": "string", "description": "Alias for pathScope"],
                "fileType": ["type": "string", "description": "File type filter (e.g. 'swift', 'ts', 'py')"],
                "glob": ["type": "string", "description": "Glob pattern to filter files (e.g. '*.swift', '*.{ts,tsx}')"],
                "output_mode": ["type": "string", "description": "'content' (default), 'files_only' (just paths), or 'count' (match counts)"],
                "context_lines": ["type": "string", "description": "Context lines around matches (default: 2, max: 10). Only for 'content' mode"],
                "case_sensitive": ["type": "string", "description": "'true' or 'false' (default: false)"],
                "multiline": ["type": "string", "description": "'true' for multiline regex matching (default: false)"]
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
            description: "Run shell command. The working directory defaults to the workspace root (the project folder paths listed in the context). Always operate within the workspace — never search the full filesystem unless explicitly asked.",
            properties: [
                "command": ["type": "string", "description": "Shell command to execute. Paths should be relative to the workspace root."],
                "cwd": ["type": "string", "description": "Optional working directory override. Defaults to the workspace root."]
            ],
            required: ["command"]
        ),
        ToolSchemaEntry(
            name: "read_terminal",
            description: "Read the output from the IDE terminal. Can read the active session or all sessions. Use this to see what the user ran in their terminal.",
            properties: [
                "session_id": ["type": "string", "description": "Optional session ID to read from. If omitted, reads the active terminal session."],
                "last_n": ["type": "string", "description": "Number of characters to read from the end of the terminal buffer. Default 8000."],
                "all_sessions": ["type": "string", "description": "Set to 'true' to read a summary of all terminal sessions."]
            ],
            required: []
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
            description: "List directory contents with optional tree view. Supports recursive listing with depth control and file sizes.",
            properties: [
                "path": ["type": "string", "description": "Directory path"],
                "recursive": ["type": "string", "description": "Set to 'true' to list recursively as a tree (default: false)"],
                "depth": ["type": "string", "description": "Max depth for recursive listing (default: 3, max: 5)"],
                "sizes": ["type": "string", "description": "Set to 'true' to show file sizes (default: false)"],
                "maxEntries": ["type": "string", "description": "Max entries to return (default: 200, max: 2000)"]
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
                "test": ["type": "string", "description": "Test name or filter"],
                "target": ["type": "string", "description": "Optional test target"]
            ],
            required: ["test"]
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
            required: ["query"]
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
                "query": ["type": "string", "description": "Current symbol name to rename"],
                "new_name": ["type": "string", "description": "New symbol name"],
                "kind": ["type": "string", "description": "Optional symbol kind"]
            ],
            required: ["query", "new_name"]
        ),
        ToolSchemaEntry(
            name: "find_and_replace_all",
            description: "Run workspace-wide find and replace",
            properties: [
                "pattern": ["type": "string", "description": "Search text or regex pattern"],
                "replacement": ["type": "string", "description": "Replacement text"],
                "file_type": ["type": "string", "description": "Optional file type filter"],
                "regex": ["type": "string", "description": "true if pattern is a regex, false otherwise"]
            ],
            required: ["pattern", "replacement"]
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
            name: "todo_write",
            description: "Create or update todo items in the LiveCard/task panel",
            properties: [
                "title": ["type": "string", "description": "Todo title (single-item mode)"],
                "status": ["type": "string", "description": "pending|in_progress|done|blocked"],
                "priority": ["type": "string", "description": "low|medium|high"],
                "notes": ["type": "string", "description": "Optional note"],
                "activeForm": ["type": "string", "description": "Optional present-tense activity label"],
                "linkedFiles": ["type": "string", "description": "Optional JSON array of related file paths"],
                "todos": ["type": "string", "description": "Optional JSON array of todo items for batch updates"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "todo_read",
            description: "Read the current todo list from the LiveCard/task panel",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "plan_step_update",
            description: "Update a plan step status in the plan panel",
            properties: [
                "step_id": ["type": "string", "description": "Plan step identifier"],
                "status": ["type": "string", "description": "pending|running|done|failed"],
                "title": ["type": "string", "description": "Optional step title"]
            ],
            required: ["step_id", "status"]
        ),
        ToolSchemaEntry(
            name: "mermaid_render",
            description: "Render a Mermaid diagram in the IDE plan/chat panels",
            properties: [
                "code": ["type": "string", "description": "Mermaid diagram source code"],
                "title": ["type": "string", "description": "Optional diagram title"]
            ],
            required: ["code"]
        ),
        ToolSchemaEntry(
            name: "policy_ack",
            description: "Acknowledge the required policy hash before operational tool calls",
            properties: [
                "hash": ["type": "string", "description": "Policy hash from context"]
            ],
            required: ["hash"]
        ),
        ToolSchemaEntry(
            name: "activate_plan_mode",
            description: "Activate the plan panel in the IDE",
            properties: [
                "reason": ["type": "string", "description": "Optional reason for activation"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "activate_debug_mode",
            description: "Activate the debug panel in the IDE",
            properties: [
                "reason": ["type": "string", "description": "Optional reason for activation"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "show_task_panel",
            description: "Open/focus the task panel in the IDE",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "show_swarm_panel",
            description: "Open/focus the swarm panel in the IDE",
            properties: [
                "swarm_id": ["type": "string", "description": "Optional swarm id to focus"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "subagent_explorer",
            description: "Spawn a read-only explorer subagent for parallel codebase investigation",
            properties: [
                "task": ["type": "string", "description": "Task to investigate"]
            ],
            required: ["task"]
        ),
        ToolSchemaEntry(
            name: "subagent_coder",
            description: "Spawn a coding subagent for implementation work",
            properties: [
                "task": ["type": "string", "description": "Implementation task"]
            ],
            required: ["task"]
        ),
        ToolSchemaEntry(
            name: "subagent_debugger",
            description: "Spawn a debugger subagent for bug investigation/fixes",
            properties: [
                "task": ["type": "string", "description": "Debug task"]
            ],
            required: ["task"]
        ),
        ToolSchemaEntry(
            name: "subagent_reviewer",
            description: "Spawn a reviewer subagent for quality/code-review checks",
            properties: [
                "task": ["type": "string", "description": "Review task"]
            ],
            required: ["task"]
        ),
        ToolSchemaEntry(
            name: "subagent_testWriter",
            description: "Spawn a test-writer subagent for test creation and verification",
            properties: [
                "task": ["type": "string", "description": "Testing task"]
            ],
            required: ["task"]
        ),
        ToolSchemaEntry(
            name: "subagent_tester",
            description: "Legacy alias of subagent_testWriter",
            properties: [
                "task": ["type": "string", "description": "Testing task"]
            ],
            required: ["task"]
        ),
        ToolSchemaEntry(
            name: "subagent_docWriter",
            description: "Spawn a documentation subagent for docs/changelog updates",
            properties: [
                "task": ["type": "string", "description": "Documentation task"]
            ],
            required: ["task"]
        ),
        ToolSchemaEntry(
            name: "subagent_securityAuditor",
            description: "Spawn a security-auditor subagent for security analysis",
            properties: [
                "task": ["type": "string", "description": "Security audit task"]
            ],
            required: ["task"]
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
        ),

        // MARK: Browser Tools
        ToolSchemaEntry(
            name: "browser_navigate",
            description: "Navigate the integrated browser to a URL. Opens the browser panel if not already visible.",
            properties: [
                "url": ["type": "string", "description": "URL to navigate to (e.g. http://localhost:3000)"]
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
