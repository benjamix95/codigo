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
    private var _sourceFingerprint = ""

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

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        _entries.removeAll()
        _routing.removeAll()
        _rawSchemas.removeAll()
        _sourceFingerprint = ""
    }

    /// Register MCP tools as native function tools.
    /// Creates normalized function names and routing entries.
    @discardableResult
    func register(tools: [MCPToolDescriptor]) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let fingerprint = Self.descriptorFingerprint(for: tools)
        if fingerprint == _sourceFingerprint {
            return false
        }

        _entries.removeAll()
        _routing.removeAll()
        _rawSchemas.removeAll()
        _sourceFingerprint = fingerprint

        var nameCount: [String: Int] = [:]
        for tool in tools {
            nameCount[tool.name, default: 0] += 1
        }

        let sortedTools = tools.sorted { lhs, rhs in
            if lhs.serverId != rhs.serverId { return lhs.serverId < rhs.serverId }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.schema < rhs.schema
        }
        var usedFunctionNames = Set<String>()

        for tool in sortedTools {
            let needsPrefix = nameCount[tool.name, default: 0] > 1
            let baseFunctionName = Self.normalizeFunctionName(
                serverName: tool.serverName,
                toolName: tool.name,
                needsPrefix: needsPrefix
            )
            let functionName = Self.resolveUniqueFunctionName(
                base: baseFunctionName,
                serverId: tool.serverId,
                toolName: tool.name,
                usedNames: &usedFunctionNames
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
        return true
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

    private static func resolveUniqueFunctionName(
        base: String,
        serverId: String,
        toolName: String,
        usedNames: inout Set<String>
    ) -> String {
        let normalizedBase = base.isEmpty ? "mcp_tool" : String(base.prefix(64))
        if usedNames.insert(normalizedBase).inserted {
            return normalizedBase
        }

        let stableSuffix = deterministicSuffix(seed: "\(serverId)|\(toolName)|\(normalizedBase)")
        var attempt = 0
        while true {
            let suffix = attempt == 0 ? stableSuffix : "\(stableSuffix)\(attempt)"
            let maxBaseLength = max(1, 64 - suffix.count - 1)
            let truncatedBase = String(normalizedBase.prefix(maxBaseLength))
            let candidate = "\(truncatedBase)_\(suffix)"
            if usedNames.insert(candidate).inserted {
                return candidate
            }
            attempt += 1
        }
    }

    private static func deterministicSuffix(seed: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        let base36 = String(hash, radix: 36)
        let suffix = String(base36.suffix(8))
        return suffix.isEmpty ? "0" : suffix
    }

    private static func descriptorFingerprint(for tools: [MCPToolDescriptor]) -> String {
        let lines = tools
            .sorted { lhs, rhs in
                if lhs.serverId != rhs.serverId { return lhs.serverId < rhs.serverId }
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.schema < rhs.schema
            }
            .map { descriptor in
                "\(descriptor.serverId)|\(descriptor.serverName)|\(descriptor.name)|\(descriptor.description)|\(descriptor.schema)"
            }
        return lines.joined(separator: "\n")
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
                    if let encoded = try? JSONSerialization.data(withJSONObject: enumValues),
                       let text = String(data: encoded, encoding: .utf8) {
                        entry["enum"] = text
                    } else {
                        entry["enum"] = enumValues.joined(separator: ", ")
                    }
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
        // MARK: Debug Tools (Optimized)
        ToolSchemaEntry(
            name: "debug_context",
            description: "Gather comprehensive debugging context for the current workspace. Use at the START of every debug session (Describe phase). Collects git state, build errors, linter diagnostics, environment info, recent crash logs, dependencies, and open file context. Use 'scope' to focus on specific areas.",
            properties: [
                "scope": ["type": "string", "description": "What to collect: 'full' (default, everything), 'git' (status/diff/log only), 'build' (build errors), 'lints' (linter diagnostics), 'env' (Swift/Xcode/SDK versions), 'tests' (test listing), 'crashes' (recent crash reports). Comma-separated for multiple."],
                "include_file_content": ["type": "string", "description": "If 'true', includes source code around files with errors (20 lines context). Default: false."],
                "max_depth": ["type": "string", "description": "Max depth for directory scanning (default: 3)"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "debug_log",
            description: "Write one or more entries to the debug log. Use throughout the debug session to record observations, findings, and evidence. Supports batch mode for multiple entries in one call. Use category='runtime' or 'instrumentation' for runtime logs that link to hypotheses.",
            properties: [
                "severity": ["type": "string", "description": "error|warning|info|verbose|trace"],
                "source": ["type": "string", "description": "Source component, file:line, or module name"],
                "message": ["type": "string", "description": "Log message describing the observation"],
                "detail": ["type": "string", "description": "Extended detail: stack trace, variable dump, error context"],
                "category": ["type": "string", "description": "Category: compiler, runtime, test, network, instrumentation, custom"],
                "tags": ["type": "string", "description": "Comma-separated tags for filtering (e.g. 'memory,leak,hypothesis-1')"],
                "stack_trace": ["type": "string", "description": "Full stack trace to attach (kept separate from detail for structured access)"],
                "hypothesis_id": ["type": "string", "description": "Link this log entry to a specific hypothesis"],
                "run_id": ["type": "string", "description": "Group logs by reproduce run"],
                "data": ["type": "string", "description": "JSON object of arbitrary key-value data (variable values, timing, etc.)"],
                "batch": ["type": "string", "description": "JSON array of log entries: [{severity, source, message, detail?, category?, tags?}, ...]. When provided, other fields are ignored."]
            ],
            required: ["severity", "source", "message"]
        ),
        ToolSchemaEntry(
            name: "debug_query",
            description: "Query and analyze debug logs with powerful filtering. Use to review observations, find patterns, and correlate evidence. Supports aggregation, time filtering, hypothesis linking, and export.",
            properties: [
                "severity": ["type": "string", "description": "Filter by severity: error, warning, info, verbose, trace"],
                "category": ["type": "string", "description": "Filter by category: compiler, runtime, test, network, instrumentation"],
                "source": ["type": "string", "description": "Filter by source component or file"],
                "search": ["type": "string", "description": "Full-text search across messages and details"],
                "tags": ["type": "string", "description": "Filter by tags (comma-separated, matches any)"],
                "hypothesis_id": ["type": "string", "description": "Show only logs linked to this hypothesis"],
                "time_range": ["type": "string", "description": "Show logs from last N minutes (e.g. '5' for last 5 minutes)"],
                "group_by": ["type": "string", "description": "Aggregate results: severity, source, category, tags. Returns counts per group."],
                "format": ["type": "string", "description": "'summary' (stats overview), 'full' (all entries), 'json' (structured JSON export), 'markdown' (formatted report)"],
                "limit": ["type": "string", "description": "Maximum entries to return (default: 50, max: 500)"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "debug_session",
            description: "Manage debug sessions with lifecycle control, snapshots, and export. Use 'start' at the beginning, 'snapshot' to save state for comparison, 'stats' for session metrics, 'export' for a full report, and 'end'/'clear' to finish.",
            properties: [
                "action": ["type": "string", "description": "start|end|stop|clear|snapshot|export|stats"],
                "label": ["type": "string", "description": "Label for snapshot (used with action=snapshot). Use descriptive names like 'before-fix', 'after-refactor'."]
            ],
            required: ["action"]
        ),
        ToolSchemaEntry(
            name: "debug_hypothesize",
            description: "Propose, update, or rank debug hypotheses with structured metadata. Each hypothesis tracks a potential root cause with confidence, evidence, related files, and type classification. Use during the Fix phase to systematically narrow down the bug.",
            properties: [
                "action": ["type": "string", "description": "propose (create new) | update (modify existing)"],
                "hypothesis_id": ["type": "string", "description": "Required for update; returned by propose"],
                "title": ["type": "string", "description": "Concise hypothesis title (required for propose)"],
                "description": ["type": "string", "description": "Detailed explanation of the hypothesized root cause"],
                "status": ["type": "string", "description": "proposed|investigating|confirmed|rejected"],
                "evidence": ["type": "string", "description": "Evidence notes supporting or refuting the hypothesis"],
                "confidence": ["type": "string", "description": "Confidence level 0-100 (0=wild guess, 100=certain). Helps rank hypotheses."],
                "root_cause_type": ["type": "string", "description": "Classification: logic, concurrency, config, dependency, state, memory, type, nil_safety, api_misuse"],
                "related_files": ["type": "string", "description": "Comma-separated file paths relevant to this hypothesis"],
                "related_tests": ["type": "string", "description": "Comma-separated test names that would verify/refute this hypothesis"]
            ],
            required: ["action"]
        ),
        ToolSchemaEntry(
            name: "debug_mark",
            description: "Insert a typed debug marker or instrumentation into a file. Supports plain markers, logging statements, assertions, timing measurements, and variable captures. All markers are tracked for automatic cleanup with debug_clean. Use during Reproduce/Fix phases.",
            properties: [
                "path": ["type": "string", "description": "File path to insert the marker"],
                "line": ["type": "string", "description": "Line number (1-based) where the marker is inserted AFTER"],
                "comment": ["type": "string", "description": "Human-readable comment describing what this marker checks"],
                "code": ["type": "string", "description": "Custom code to insert (overrides type-based generation)"],
                "type": ["type": "string", "description": "'marker' (comment only, default), 'log' (print statement), 'assert' (assertion), 'timing' (execution timing), 'variable' (variable state capture)"],
                "expression": ["type": "string", "description": "Expression to log/assert/capture. For 'log': the value to print. For 'assert': the condition. For 'variable': the variable name."],
                "hypothesis_id": ["type": "string", "description": "Link this marker to a hypothesis for correlation"]
            ],
            required: ["path", "line", "comment"]
        ),
        ToolSchemaEntry(
            name: "debug_clean",
            description: "Remove debug markers and instrumentation from files. Supports selective cleanup by type, dry-run preview, and hypothesis-scoped removal. Called automatically during 'Mark Fixed' flow, but can be used manually anytime.",
            properties: [
                "path": ["type": "string", "description": "Clean only this file. If omitted, searches entire workspace."],
                "type": ["type": "string", "description": "'all' (default), 'markers' (comment-only markers), 'logs' (print statements), 'asserts' (assertions), 'timing' (timing code), 'variables' (variable captures)"],
                "dry_run": ["type": "string", "description": "If 'true', shows what would be removed without actually removing. Useful for preview."],
                "hypothesis_id": ["type": "string", "description": "Remove only markers linked to this hypothesis"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "debug_set_phase",
            description: "Set the current debug flow phase in the IDE panel. Controls the progress bar visualization. Phases: describing (gather context) -> reproducing (reproduce the bug) -> fixing (hypothesize and fix) -> instrumenting (add instrumentation) -> verifying (run tests) -> resolved (done).",
            properties: [
                "phase": ["type": "string", "description": "describing|reproducing|fixing|instrumenting|verifying|resolved"],
                "detail": ["type": "string", "description": "Brief explanation of why this phase transition is happening"]
            ],
            required: ["phase"]
        ),
        ToolSchemaEntry(
            name: "debug_request_user",
            description: "Request user input or ask them to reproduce the bug. Use 'question' to ask clarifying questions, 'reproduce' to ask the user to trigger the bug so instrumentation can capture data.",
            properties: [
                "kind": ["type": "string", "description": "question|reproduce"],
                "prompt": ["type": "string", "description": "The question or step-by-step reproduction instructions"]
            ],
            required: ["kind", "prompt"]
        ),
        ToolSchemaEntry(
            name: "debug_resolve",
            description: "Resolve the debug session with a comprehensive final summary after cleanup. Include: root cause, fix applied, verification results, and any remaining risks.",
            properties: [
                "summary": ["type": "string", "description": "Final summary: root cause, fix applied, tests passed, and any caveats"]
            ],
            required: ["summary"]
        ),

        // MARK: Debug Advanced Tools (New)
        ToolSchemaEntry(
            name: "debug_trace_analyze",
            description: "Analyze an error message, stack trace, crash log, or test failure output. Parses the text structurally, extracts file paths and line numbers, identifies the error type, and suggests files to investigate. Use in the Describe phase right after debug_context.",
            properties: [
                "error_text": ["type": "string", "description": "The error output, stack trace, crash log, or test failure to analyze"],
                "error_type": ["type": "string", "description": "'compile' (build errors), 'runtime' (crashes/exceptions), 'crash' (crash reports), 'test_failure' (test assertions), 'assertion' (precondition/assert). Auto-detected if omitted."],
                "context": ["type": "string", "description": "Additional context about when/where the error occurs"]
            ],
            required: ["error_text"]
        ),
        ToolSchemaEntry(
            name: "debug_instrument",
            description: "Insert intelligent, executable instrumentation code into a source file. More powerful than debug_mark: generates real Swift code for logging, assertions, timing measurements, variable captures, and conditional breakpoints. All instrumentation is tracked and auto-cleaned on session resolve.",
            properties: [
                "path": ["type": "string", "description": "File to instrument"],
                "line": ["type": "string", "description": "Line number (1-based) — code is inserted AFTER this line"],
                "type": ["type": "string", "description": "'log' (print expression value), 'assert' (assert condition), 'timing' (measure execution time of the enclosing scope), 'variable' (capture and print variable state), 'conditional_break' (log only when condition is true)"],
                "expression": ["type": "string", "description": "The expression to log/assert/capture. For 'log': value to print. For 'assert': boolean condition. For 'variable': variable name. For 'conditional_break': guard condition."],
                "condition": ["type": "string", "description": "For 'conditional_break': only log when this condition is true. For 'assert': custom failure message."],
                "hypothesis_id": ["type": "string", "description": "Link this instrumentation to a hypothesis"],
                "label": ["type": "string", "description": "Human-readable label for this instrumentation point (shown in debug panel)"]
            ],
            required: ["path", "line", "type", "expression"]
        ),
        ToolSchemaEntry(
            name: "debug_timeline",
            description: "Generate a chronological timeline of all debug events in the current session: logs, phase changes, hypotheses, markers, instrumentation. Helps understand the sequence of observations and decisions. Use for analysis and final reporting.",
            properties: [
                "filter": ["type": "string", "description": "'all' (default), 'logs', 'hypotheses', 'markers', 'phases'. Comma-separated for multiple."],
                "time_range": ["type": "string", "description": "Show events from last N minutes"],
                "hypothesis_id": ["type": "string", "description": "Show only events linked to this hypothesis"],
                "format": ["type": "string", "description": "'text' (default, chronological list), 'mermaid' (Mermaid sequence diagram)"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "debug_snapshot",
            description: "Capture, compare, or list debug session snapshots. Snapshots save the full debug state (phase, hypotheses, markers, log counts, file changes) at a point in time. Use before and after each fix attempt to track progress and detect regressions.",
            properties: [
                "action": ["type": "string", "description": "'capture' (save current state), 'compare' (diff two snapshots), 'list' (show all snapshots)"],
                "label": ["type": "string", "description": "Descriptive label for the snapshot (e.g. 'before-fix', 'after-refactor'). Required for capture."],
                "compare_with": ["type": "string", "description": "Label of the snapshot to compare against (used with action=compare)"]
            ],
            required: ["action"]
        ),
        ToolSchemaEntry(
            name: "debug_test_check",
            description: "Run a targeted Swift Package test check to verify a fix or detect regressions. More focused than run_tests: identifies tests related to specific files, runs only those, and compares results with previous runs. Use in the Verify phase after applying a fix.",
            properties: [
                "scope": ["type": "string", "description": "'all' (run all tests), 'related' (tests related to modified files), 'failing' (only previously failing tests), 'file' (tests in/for a specific file)"],
                "path": ["type": "string", "description": "File path to find related tests for (used with scope=file or scope=related)"],
                "filter": ["type": "string", "description": "Test name filter pattern"],
                "hypothesis_id": ["type": "string", "description": "Run tests related to the files in this hypothesis"],
                "timeout_ms": ["type": "string", "description": "Timeout in milliseconds (default: 60000)"]
            ],
            required: []
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
