import Foundation

public struct ToolCall: Sendable {
    public let id: String
    public let name: String
    public let args: [String: String]
    public let sourceProvider: String
    public let swarmId: String?
    public let scope: ExecutionScope
}

public struct ToolResult: Sendable {
    public let ok: Bool
    public let payload: [String: String]
    public let durationMs: Int
}

public enum ToolRuntimeError: LocalizedError, Sendable {
    case validation(String)
    case timeout(tool: String, ms: Int)
    case budgetExceeded(String)
    case mcpUnavailable(String)
    case transport(String)
    case sandboxViolation(String)

    public var errorDescription: String? {
        switch self {
        case .validation(let msg): return msg
        case .timeout(let tool, let ms): return "Timeout on \(tool) (\(ms)ms)"
        case .budgetExceeded(let msg): return msg
        case .mcpUnavailable(let msg): return msg
        case .transport(let msg): return msg
        case .sandboxViolation(let msg): return msg
        }
    }

    public var errorCode: String {
        switch self {
        case .validation: return "validation"
        case .timeout: return "timeout"
        case .budgetExceeded: return "budget_exceeded"
        case .mcpUnavailable: return "mcp_unavailable"
        case .transport: return "transport"
        case .sandboxViolation: return "sandbox_violation"
        }
    }
}

public struct ToolRuntimePolicy: Sendable {
    public let sandboxMode: String
    public let askForApproval: String
    public let timeoutMs: Int
    public let maxToolCallsPerRound: Int
    public let maxRepeatedSameToolPerRound: Int
    public let maxBashOutputBytes: Int
    public let maxReadBytesPerFile: Int
    public let allowDangerousShellPatterns: Bool
    public let enableMCP: Bool
    public let mcpPerCallTimeoutMs: Int
    public let mcpSessionIdleTTLSeconds: Int

    public init(
        sandboxMode: String = "workspace-write",
        askForApproval: String = "never",
        timeoutMs: Int = 60_000,
        maxToolCallsPerRound: Int = 15,
        maxRepeatedSameToolPerRound: Int = 8,
        maxBashOutputBytes: Int = 128_000,
        maxReadBytesPerFile: Int = 256_000,
        allowDangerousShellPatterns: Bool = false,
        enableMCP: Bool = true,
        mcpPerCallTimeoutMs: Int = 30_000,
        mcpSessionIdleTTLSeconds: Int = 300
    ) {
        self.sandboxMode = sandboxMode
        self.askForApproval = askForApproval
        self.timeoutMs = timeoutMs
        self.maxToolCallsPerRound = max(1, maxToolCallsPerRound)
        self.maxRepeatedSameToolPerRound = max(1, maxRepeatedSameToolPerRound)
        self.maxBashOutputBytes = max(1_024, maxBashOutputBytes)
        self.maxReadBytesPerFile = max(1_024, maxReadBytesPerFile)
        self.allowDangerousShellPatterns = allowDangerousShellPatterns
        self.enableMCP = enableMCP
        self.mcpPerCallTimeoutMs = max(1_000, mcpPerCallTimeoutMs)
        self.mcpSessionIdleTTLSeconds = max(60, mcpSessionIdleTTLSeconds)
    }
}

public struct ToolExecutionContext: Sendable {
    public let workspaceContext: WorkspaceContext
    public let policy: ToolRuntimePolicy
    public let executionScope: ExecutionScope

    public init(
        workspaceContext: WorkspaceContext,
        policy: ToolRuntimePolicy = ToolRuntimePolicy(),
        executionScope: ExecutionScope = .agent
    ) {
        self.workspaceContext = workspaceContext
        self.policy = policy
        self.executionScope = executionScope
    }
}

public actor UnifiedToolRuntime {
    private let executionController: ExecutionController?
    private let executionScope: ExecutionScope
    private let mcpSessions: MCPSessionManager

    /// Codebase index tools (nil when no index is available)
    private let indexTools: CodebaseIndexTools?
    /// Direct reference to CodebaseIndex for SemanticIndex access
    private let codebaseIndex: CodebaseIndex?
    private let workspacePaths: [URL]
    private let excludedPaths: [String]

    /// Web search service (Brave Search + DuckDuckGo fallback)
    private let webSearch: WebSearchService
    /// Web fetch service (HTML → Markdown)
    private let webFetch: WebFetchService

    /// Debug log server for structured debug logging
    public let debugLogServer = DebugLogServer()

    public init(
        executionController: ExecutionController? = nil,
        executionScope: ExecutionScope = .agent,
        mcpSessions: MCPSessionManager = MCPSessionManager(),
        index: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        excludedPaths: [String] = [],
        webSearchProvider: String? = nil,
        webSearchApiKeys: [String: String]? = nil
    ) {
        self.executionController = executionController
        self.executionScope = executionScope
        self.mcpSessions = mcpSessions
        self.codebaseIndex = index
        self.indexTools = index.map { CodebaseIndexTools(index: $0) }
        self.workspacePaths = workspacePaths
        self.excludedPaths = excludedPaths

        // Build web search service from provider + keys map
        let provider = WebSearchProvider(rawValue: webSearchProvider ?? "") ?? .duckduckgo
        var typedKeys: [WebSearchProvider: String] = [:]
        if let keys = webSearchApiKeys {
            for (rawKey, value) in keys {
                if let p = WebSearchProvider(rawValue: rawKey) {
                    typedKeys[p] = value
                }
            }
        }
        self.webSearch = WebSearchService(provider: provider, apiKeys: typedKeys)
        self.webFetch = WebFetchService()
    }

    /// Run an external process and return (stdout, stderr, exitCode).
    /// A lightweight wrapper around ProcessRunner for tools that need simple exec.
    private func shellExec(
        args: [String],
        cwd: String,
        timeout: Int = 30_000
    ) async -> (String, String, Int32) {
        guard !args.isEmpty else { return ("", "argument list is empty", 1) }
        let executable = args[0]
        let arguments = Array(args.dropFirst())
        do {
            let result = try await ProcessRunner.runCollecting(
                executable: executable,
                arguments: arguments,
                workingDirectory: URL(fileURLWithPath: cwd),
                executionController: executionController,
                scope: executionScope
            )
            let stdout = result.output.joined(separator: "\n")
            return (stdout, "", result.terminationStatus)
        } catch {
            return ("", error.localizedDescription, 1)
        }
    }

    public func execute(_ call: ToolCall, context: ToolExecutionContext) async -> [StreamEvent] {
        let normalizedName = normalizeToolName(call.name)
        let start = Date()
        let basePayload = buildBasePayload(call: call, normalizedName: normalizedName)

        var events: [StreamEvent] = [.raw(type: "mcp_tool_call", payload: basePayload)]
        let result = await run(call, normalizedName: normalizedName, context: context, startDate: start)

        var completedPayload = result.payload
        completedPayload["tool_call_id"] = call.id
        completedPayload["tool"] = normalizedName
        completedPayload["duration_ms"] = "\(result.durationMs)"
        completedPayload["status"] = result.ok ? "completed" : "failed"
        if let swarmId = call.swarmId, !swarmId.isEmpty {
            completedPayload["swarm_id"] = swarmId
            completedPayload["group_id"] = "swarm-\(swarmId)"
        }

        let eventType = eventTypeForTool(name: normalizedName, ok: result.ok)
        events.append(.raw(type: eventType, payload: completedPayload))
        return events
    }

    private func run(
        _ call: ToolCall,
        normalizedName: String,
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult {
        do {
            try validate(call: call, normalizedName: normalizedName)

            switch normalizedName {
            case "read":
                return try executeRead(call: call, context: context, startDate: startDate)
            case "read_range":
                return try executeReadRange(call: call, context: context, startDate: startDate)
            case "list_dir":
                return try executeListDir(call: call, context: context, startDate: startDate)
            case "git_diff":
                return await executeGitDiff(call: call, context: context, startDate: startDate)
            case "search_symbols":
                return await executeSearchSymbols(call: call, context: context, startDate: startDate)
            case "run_tests":
                return await executeRunTests(call: call, context: context, startDate: startDate)
            case "build_project":
                return await executeBuildProject(call: call, context: context, startDate: startDate)
            case "list_processes":
                return await executeListProcesses(call: call, context: context, startDate: startDate)
            case "read_json":
                return try executeReadJSON(call: call, context: context, startDate: startDate)
            case "write_json":
                return try executeWriteJSON(call: call, context: context, startDate: startDate)
            case "workspace_stats":
                return await executeWorkspaceStats(call: call, context: context, startDate: startDate)
            case "dependency_audit":
                return await executeDependencyAudit(call: call, context: context, startDate: startDate)
            case "tail_log":
                return await executeTailLog(call: call, context: context, startDate: startDate)
            case "glob":
                return await executeGlob(call: call, context: context, startDate: startDate)
            case "grep":
                return await executeGrep(call: call, context: context, startDate: startDate)
            case "str_replace":
                return try executeStrReplace(call: call, context: context, startDate: startDate)
            case "create_file":
                return try executeCreateFile(call: call, context: context, startDate: startDate)
            case "edit", "write":
                // If old_string is present, behave like str_replace for backward compatibility
                if let oldStr = call.args["old_string"], !oldStr.isEmpty {
                    return try executeStrReplace(call: call, context: context, startDate: startDate)
                }
                return try executeWrite(call: call, context: context, startDate: startDate)
            case "bash":
                let command = call.args["command"] ?? ""
                return await runBash(
                    command: command,
                    cwd: context.workspaceContext.workspacePath,
                    startDate: startDate,
                    title: "Bash",
                    timeoutMs: context.policy.timeoutMs,
                    maxOutputBytes: context.policy.maxBashOutputBytes,
                    policy: context.policy
                )
            case "web_search":
                return await executeWebSearch(call: call, context: context, startDate: startDate)
            case "web_fetch":
                return await executeWebFetch(call: call, context: context, startDate: startDate)
            // New Cursor-style tools
            case "parallel_apply":
                return try await executeParallelApply(call: call, context: context, startDate: startDate)
            case "regex_replace":
                return try executeRegexReplace(call: call, context: context, startDate: startDate)
            case "attempt_completion":
                return await executeAttemptCompletion(call: call, context: context, startDate: startDate)
            case "diagnostics":
                return await executeDiagnostics(call: call, context: context, startDate: startDate)

            // New powerful tools
            case "rename_symbol":
                return await executeRenameSymbol(call: call, context: context, startDate: startDate)
            case "find_and_replace_all":
                return await executeFindAndReplaceAll(call: call, context: context, startDate: startDate)
            case "undo_edit":
                return await executeUndoEdit(call: call, context: context, startDate: startDate)
            case "run_single_test":
                return await executeRunSingleTest(call: call, context: context, startDate: startDate)

            // Debug tools
            case "debug_log":
                return await executeDebugLog(call: call, context: context, startDate: startDate)
            case "debug_query":
                return await executeDebugQuery(call: call, context: context, startDate: startDate)
            case "debug_session":
                return await executeDebugSession(call: call, context: context, startDate: startDate)
            case "debug_hypothesize":
                return await executeDebugHypothesize(call: call, context: context, startDate: startDate)
            case "debug_mark":
                return await executeDebugMark(call: call, context: context, startDate: startDate)
            case "debug_clean":
                return await executeDebugClean(call: call, context: context, startDate: startDate)

            // Cursor-style semantic tools
            case "semantic_search":
                return await executeSemanticSearch(call: call, context: context, startDate: startDate)
            case "read_lints":
                return await executeReadLints(call: call, context: context, startDate: startDate)
            case "debug_context":
                return await executeDebugContext(call: call, context: context, startDate: startDate)

            // Codebase index tools (13 tools)
            case "codebase_search", "find_symbol", "list_symbols", "find_references",
                 "project_structure", "file_outline", "find_files", "codebase_stats",
                 "dependency_graph", "list_types", "list_tests", "index_status", "reindex":
                return await executeIndexTool(name: normalizedName, call: call, context: context, startDate: startDate)

            case "mcp", "mcp_call":
                return await executeMCPCall(call: call, context: context, startDate: startDate)
            case "mcp_list_tools":
                return await executeMCPListTools(call: call, context: context, startDate: startDate)
            case "mcp_describe_tool":
                return await executeMCPDescribeTool(call: call, context: context, startDate: startDate)
            case "mcp_health":
                return await executeMCPHealth(call: call, context: context, startDate: startDate)
            case "mcp_list_servers":
                return await executeMCPListServers(context: context, startDate: startDate)
            case "mcp_reconnect":
                return await executeMCPReconnect(call: call, context: context, startDate: startDate)
            default:
                if context.policy.enableMCP {
                    return await executeMCPDirectToolFallback(
                        toolName: normalizedName,
                        call: call,
                        context: context,
                        startDate: startDate
                    )
                }
                throw ToolRuntimeError.validation("Tool non supportato: \(normalizedName)")
            }
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate)
        } catch {
            return failure(error.localizedDescription, errorCode: "unknown", startDate: startDate)
        }
    }

    public func executeMCP(call: ToolCall, context: ToolExecutionContext) async -> ToolResult {
        await executeMCPCall(call: call, context: context, startDate: Date())
    }

    private func executeMCPCall(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate
            )
        }

        let requestedToolRaw = (call.args["tool"] ?? call.args["mcp_tool"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let serverArg = (call.args["server"] ?? call.args["server_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let serverId: String?
        let toolName: String
        if requestedToolRaw.contains("/") {
            let parts = requestedToolRaw.split(separator: "/", maxSplits: 1).map(String.init)
            serverId = parts.first
            toolName = parts.count > 1 ? parts[1] : ""
        } else {
            serverId = serverArg.isEmpty ? nil : serverArg
            toolName = requestedToolRaw
        }

        guard !toolName.isEmpty else {
            return failure(
                "Missing MCP tool name",
                errorCode: ToolRuntimeError.validation("Missing MCP tool name").errorCode,
                startDate: startDate
            )
        }

        var args = call.args
        let embeddedArgs = parseEmbeddedArgs(call.args["args"])
        for (k, v) in embeddedArgs { args[k] = v }
        args.removeValue(forKey: "name")
        args.removeValue(forKey: "id")
        args.removeValue(forKey: "tool")
        args.removeValue(forKey: "mcp_tool")
        args.removeValue(forKey: "server")
        args.removeValue(forKey: "server_id")
        args.removeValue(forKey: "args")

        do {
            let result = try await mcpSessions.callTool(
                serverId: serverId,
                toolName: toolName,
                arguments: args,
                timeoutMs: context.policy.mcpPerCallTimeoutMs,
                idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
            )

            var payload: [String: String] = [
                "title": "MCP \(result.serverName)/\(toolName)",
                "tool": "mcp",
                "mcp_server": result.serverName,
                "server_id": result.serverId,
                "mcp_tool": toolName,
                "output": truncate(result.content, maxBytes: context.policy.maxBashOutputBytes),
                "mcp_latency_ms": "\(max(1, Int(Date().timeIntervalSince(startDate) * 1000)))"
            ]
            if result.isError {
                payload["detail"] = "MCP server responded with isError=true"
            }
            return ToolResult(
                ok: !result.isError,
                payload: payload,
                durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000))
            )
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: [
                "mcp_tool": toolName,
                "server_id": serverId ?? ""
            ])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: [
                "mcp_tool": toolName,
                "server_id": serverId ?? ""
            ])
        }
    }

    private func executeMCPListTools(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate
            )
        }

        do {
            let serverId = call.args["server"] ?? call.args["server_id"]
            let tools = try await mcpSessions.listTools(
                serverId: serverId,
                idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
            )
            let lines = tools.map { "\($0.serverId)/\($0.name): \($0.description)" }
            return success([
                "title": "MCP tool discovery",
                "tool": "mcp_list_tools",
                "server_id": serverId ?? "",
                "output": truncate(lines.joined(separator: "\n"), maxBytes: context.policy.maxBashOutputBytes),
                "detail": "\(tools.count) tools discovered"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate)
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate)
        }
    }

    private func executeMCPDescribeTool(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate
            )
        }
        let toolName = (call.args["tool"] ?? call.args["mcp_tool"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolName.isEmpty else {
            return failure(
                "Missing tool name",
                errorCode: ToolRuntimeError.validation("tool missing").errorCode,
                startDate: startDate
            )
        }

        do {
            let serverId = call.args["server"] ?? call.args["server_id"]
            let desc = try await mcpSessions.describeTool(serverId: serverId, toolName: toolName)
            guard let desc else {
                return failure(
                    "MCP tool not found",
                    errorCode: ToolRuntimeError.mcpUnavailable("MCP tool not found").errorCode,
                    startDate: startDate
                )
            }
            return success([
                "title": "MCP describe \(desc.name)",
                "tool": "mcp_describe_tool",
                "server_id": desc.serverId,
                "mcp_tool": desc.name,
                "detail": desc.description,
                "output": truncate(desc.schema, maxBytes: context.policy.maxBashOutputBytes)
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate)
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate)
        }
    }

    private func executeMCPHealth(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate
            )
        }
        let server = call.args["server"] ?? call.args["server_id"]
        let states = await mcpSessions.health(serverId: server)
        let lines = states.keys.sorted().map { "\($0): \(states[$0] ?? "unknown")" }
        return success([
            "title": "MCP health",
            "tool": "mcp_health",
            "server_id": server ?? "",
            "output": lines.joined(separator: "\n"),
            "detail": "\(states.count) servers"
        ], startDate: startDate)
    }

    private func executeMCPListServers(context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate
            )
        }
        let servers = await mcpSessions.listServers()
        let lines = servers.map { "\($0.id) (\($0.name)) [\($0.source)]" }
        return success([
            "title": "MCP servers",
            "tool": "mcp_list_servers",
            "output": lines.joined(separator: "\n"),
            "detail": "\(servers.count) servers"
        ], startDate: startDate)
    }

    private func executeMCPReconnect(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate
            )
        }
        let serverId = (call.args["server"] ?? call.args["server_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serverId.isEmpty else {
            return failure("Missing required server", errorCode: "validation", startDate: startDate)
        }
        do {
            try await mcpSessions.reconnect(serverId: serverId)
            return success([
                "title": "MCP reconnect",
                "tool": "mcp_reconnect",
                "server_id": serverId,
                "detail": "Connection re-established"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate)
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate)
        }
    }

    private func executeMCPDirectToolFallback(
        toolName: String,
        call: ToolCall,
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult {
        do {
            var args = call.args
            let embedded = parseEmbeddedArgs(call.args["args"])
            for (k, v) in embedded { args[k] = v }
            args.removeValue(forKey: "args")
            let result = try await mcpSessions.callTool(
                serverId: call.args["server"] ?? call.args["server_id"],
                toolName: toolName,
                arguments: args,
                timeoutMs: context.policy.mcpPerCallTimeoutMs,
                idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
            )
            return success([
                "title": "MCP fallback \(result.serverName)/\(toolName)",
                "tool": toolName,
                "server_id": result.serverId,
                "mcp_server": result.serverName,
                "mcp_tool": toolName,
                "output": truncate(result.content, maxBytes: context.policy.maxBashOutputBytes)
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            if err.errorCode == "mcp_unavailable" {
                return failure("Tool non supportato: \(toolName)", errorCode: "validation", startDate: startDate)
            }
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate)
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate)
        }
    }

    private func executeRead(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let path = try resolveRequiredPath(call.args["path"], context: context)
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw ToolRuntimeError.validation("File not found: \(path)")
        }
        defer { try? handle.close() }
        let data = try handle.read(upToCount: context.policy.maxReadBytesPerFile) ?? Data()
        let rawContent = String(data: data, encoding: .utf8) ?? ""
        // Add line numbers for better readability (like cat -n)
        let lines = rawContent.components(separatedBy: "\n")
        let digitCount = max(1, String(lines.count).count)
        let numberedLines = lines.enumerated().map { idx, line in
            let num = String(idx + 1)
            let padding = String(repeating: " ", count: max(0, digitCount - num.count))
            return "\(padding)\(num)│\(line)"
        }
        let content = numberedLines.joined(separator: "\n")
        return success([
            "title": "Read \(path)",
            "path": path,
            "output": content,
            "detail": "\(lines.count) lines"
        ], startDate: startDate)
    }

    private func executeReadRange(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let path = try resolveRequiredPath(call.args["path"], context: context)
        let startLine = max(1, Int(call.args["start"] ?? "1") ?? 1)
        let endLineRaw = Int(call.args["end"] ?? "0") ?? 0
        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let lines = content.components(separatedBy: .newlines)
        let endLine = endLineRaw > 0 ? min(lines.count, endLineRaw) : min(lines.count, startLine + 200)
        if startLine > endLine || startLine > lines.count {
            throw ToolRuntimeError.validation("Intervallo linee non valido")
        }
        let segment = lines[(startLine - 1)..<endLine].enumerated().map { idx, line in
            "\(startLine + idx): \(line)"
        }.joined(separator: "\n")
        return success([
            "title": "Read range \(path):\(startLine)-\(endLine)",
            "path": path,
            "output": truncate(segment, maxBytes: context.policy.maxReadBytesPerFile)
        ], startDate: startDate)
    }

    private func executeListDir(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let path = try resolveRequiredPath(call.args["path"] ?? ".", context: context)
        let maxEntries = max(1, min(1000, Int(call.args["maxEntries"] ?? "200") ?? 200))
        let url = URL(fileURLWithPath: path)
        let entries = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let sorted = entries
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(maxEntries)
            .map { $0.lastPathComponent }
        return success([
            "title": "List dir \(path)",
            "path": path,
            "detail": "\(sorted.count) elementi",
            "output": sorted.joined(separator: "\n")
        ], startDate: startDate)
    }

    private func executeWrite(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        guard let pathArg = call.args["path"] else {
            throw ToolRuntimeError.validation("Path mancante")
        }
        let path = try resolveRequiredPath(pathArg, context: context)
        let content = call.args["content"] ?? ""
        let oldContent = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        let added = max(0, content.split(separator: "\n").count - oldContent.split(separator: "\n").count)
        let removed = max(0, oldContent.split(separator: "\n").count - content.split(separator: "\n").count)
        let diffPreview = buildDiffPreview(old: oldContent, new: content)
        return success([
            "title": "Edit \(path)",
            "path": path,
            "file": path,
            "linesAdded": "\(added)",
            "linesRemoved": "\(removed)",
            "diffPreview": diffPreview
        ], startDate: startDate)
    }

    private func executeStrReplace(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        guard let pathArg = call.args["path"] else {
            throw ToolRuntimeError.validation("path is required")
        }
        let path = try resolveRequiredPath(pathArg, context: context)
        guard FileManager.default.fileExists(atPath: path) else {
            throw ToolRuntimeError.validation("File not found: \(path). Use create_file for new files.")
        }
        let oldString = call.args["old_string"] ?? ""
        let newString = call.args["new_string"] ?? ""

        guard !oldString.isEmpty else {
            throw ToolRuntimeError.validation("old_string is required and cannot be empty")
        }

        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""

        // Count occurrences
        let occurrences = content.components(separatedBy: oldString).count - 1

        if occurrences == 0 {
            // Try to find the closest match to help the user
            let oldLines = oldString.components(separatedBy: "\n")
            let firstLine = oldLines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var hint = ""
            if !firstLine.isEmpty {
                let contentLines = content.components(separatedBy: "\n")
                for (idx, line) in contentLines.enumerated() {
                    if line.contains(firstLine) {
                        let start = max(0, idx - 1)
                        let end = min(contentLines.count, idx + 4)
                        let snippet = contentLines[start..<end].enumerated().map { i, l in
                            "\(start + i + 1)│\(l)"
                        }.joined(separator: "\n")
                        hint = "\n\nClosest match found near line \(idx + 1):\n\(snippet)\n\nMake sure old_string matches EXACTLY including whitespace and indentation."
                        break
                    }
                }
            }
            throw ToolRuntimeError.validation("old_string not found in \(path).\(hint)")
        }

        if occurrences > 1 {
            // Find all locations to help user add context
            let contentLines = content.components(separatedBy: "\n")
            let firstOldLine = oldString.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? oldString
            var locations: [Int] = []
            for (idx, line) in contentLines.enumerated() {
                if line.contains(firstOldLine) {
                    locations.append(idx + 1)
                }
            }
            let locationStr = locations.prefix(5).map { "line \($0)" }.joined(separator: ", ")
            throw ToolRuntimeError.validation("old_string is not unique — found \(occurrences) occurrences at \(locationStr). Add more surrounding context to make it unique.")
        }

        // Perform the replacement (exactly 1 match)
        let newContent = content.replacingOccurrences(of: oldString, with: newString)
        try newContent.write(toFile: path, atomically: true, encoding: .utf8)

        // Build a nice diff preview
        let oldLines = oldString.components(separatedBy: "\n")
        let newLines = newString.components(separatedBy: "\n")
        var diffPreview = ""
        for line in oldLines.prefix(15) {
            diffPreview += "- \(line)\n"
        }
        for line in newLines.prefix(15) {
            diffPreview += "+ \(line)\n"
        }

        // Find the line number where the change was made
        let lineNumber: Int
        if let range = content.range(of: oldString) {
            let beforeReplacement = content[content.startIndex..<range.lowerBound]
            lineNumber = beforeReplacement.filter { $0 == "\n" }.count + 1
        } else {
            lineNumber = 1
        }

        return success([
            "title": "str_replace \((path as NSString).lastPathComponent):\(lineNumber)",
            "path": path,
            "file": path,
            "detail": "Replaced at line \(lineNumber) (\(oldLines.count) lines → \(newLines.count) lines)",
            "diffPreview": diffPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        ], startDate: startDate)
    }

    private func executeCreateFile(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        guard let pathArg = call.args["path"] else {
            throw ToolRuntimeError.validation("path is required")
        }
        let path = try resolveRequiredPath(pathArg, context: context)
        let content = call.args["content"] ?? ""

        if FileManager.default.fileExists(atPath: path) {
            throw ToolRuntimeError.validation("File already exists: \(path). Use str_replace to edit or write to overwrite.")
        }

        // Create intermediate directories if needed
        let dirPath = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dirPath) {
            try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }

        try content.write(toFile: path, atomically: true, encoding: .utf8)
        let lineCount = content.components(separatedBy: "\n").count
        return success([
            "title": "Created \((path as NSString).lastPathComponent)",
            "path": path,
            "file": path,
            "detail": "Created \(lineCount) lines",
            "linesAdded": "\(lineCount)"
        ], startDate: startDate)
    }

    private func executeGitDiff(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let scope = call.args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cmd = scope.isEmpty ? "git diff -- ." : "git diff -- '\(shellEscaped(scope))'"
        return await runBash(
            command: cmd,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Git diff",
            timeoutMs: context.policy.timeoutMs,
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )
    }

    private func executeSearchSymbols(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let query = (call.args["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return failure("query mancante", errorCode: "validation", startDate: startDate)
        }

        // Prefer index-powered search if available (supports all languages)
        if let indexTools {
            let events = await indexTools.execute(
                toolName: "codebase_search",
                args: call.args,
                callId: call.id,
                workspacePaths: workspacePaths,
                excludedPaths: excludedPaths
            )
            let result = toolResultFromIndexEvents(events, startDate: startDate)
            if result.ok, let output = result.payload["output"], !output.contains("No symbols found") {
                return result
            }
        }

        // Fallback to multi-language regex-based ripgrep search
        let kind = (call.args["kind"] ?? "all").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let kindPattern: String
        switch kind {
        case "class": kindPattern = "(class|Class)\\s+"
        case "struct": kindPattern = "(struct|Struct)\\s+"
        case "enum": kindPattern = "(enum|Enum)\\s+"
        case "protocol": kindPattern = "(protocol|Protocol|interface|Interface|trait)\\s+"
        case "function", "func": kindPattern = "(func|function|def|fn)\\s+"
        default: kindPattern = "(class|struct|enum|protocol|func|function|def|fn|type|trait|interface|const|let|var)\\s+"
        }
        // Search across all source file types, not just Swift
        let cmd = "rg -n \"\(kindPattern)\(shellEscaped(query))\" --type-add 'src:*.{swift,ts,tsx,js,jsx,py,go,rs,java,kt,rb,cs,php}' --type src . | head -n 200"
        return await runBash(
            command: cmd,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Search symbols \(query)",
            timeoutMs: context.policy.timeoutMs,
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )
    }

    private func executeRunTests(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let target = (call.args["target"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = (call.args["filter"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let timeoutMs = max(1_000, Int(call.args["timeout_ms"] ?? "") ?? context.policy.timeoutMs)
        var command = "swift test"
        if !target.isEmpty { command += " --filter '\(shellEscaped(target))'" }
        if !filter.isEmpty, target.isEmpty { command += " --filter '\(shellEscaped(filter))'" }
        return await runBash(
            command: command,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Run tests",
            timeoutMs: timeoutMs,
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )
    }

    private func executeBuildProject(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let configuration = (call.args["configuration"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let target = (call.args["target"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let timeoutMs = max(1_000, Int(call.args["timeout_ms"] ?? "") ?? context.policy.timeoutMs)
        var command = "swift build"
        if !configuration.isEmpty {
            command += " -c \(shellEscaped(configuration))"
        }
        if !target.isEmpty {
            command += " --target '\(shellEscaped(target))'"
        }
        return await runBash(
            command: command,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Build project",
            timeoutMs: timeoutMs,
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )
    }

    private func executeListProcesses(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let filter = (call.args["filter"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let command = filter.isEmpty
            ? "ps aux | head -n 200"
            : "ps aux | rg -i '\(shellEscaped(filter))' | head -n 200"
        return await runBash(
            command: command,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "List processes",
            timeoutMs: context.policy.timeoutMs,
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )
    }

    private func executeReadJSON(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let path = try resolveRequiredPath(call.args["path"], context: context)
        let content = try String(contentsOfFile: path, encoding: .utf8)
        guard let data = content.data(using: .utf8) else {
            throw ToolRuntimeError.validation("JSON non leggibile")
        }
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ToolRuntimeError.validation("JSON non valido")
        }
        let pretty = prettyJSON(obj)
        return success([
            "title": "Read JSON \(path)",
            "path": path,
            "output": truncate(pretty, maxBytes: context.policy.maxReadBytesPerFile)
        ], startDate: startDate)
    }

    private func executeWriteJSON(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let path = try resolveRequiredPath(call.args["path"], context: context)
        guard let patchRaw = call.args["patch"], !patchRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolRuntimeError.validation("patch JSON obbligatoria")
        }
        let patchObj = try parseJSONObject(from: patchRaw)
        let existingObj: Any
        if FileManager.default.fileExists(atPath: path) {
            let existingData = try Data(contentsOf: URL(fileURLWithPath: path))
            existingObj = try JSONSerialization.jsonObject(with: existingData)
        } else {
            existingObj = [String: Any]()
        }
        guard var merged = existingObj as? [String: Any] else {
            throw ToolRuntimeError.validation("write_json supporta solo JSON object root")
        }
        if let patchDict = patchObj as? [String: Any] {
            for (k, v) in patchDict { merged[k] = v }
        } else {
            throw ToolRuntimeError.validation("patch deve essere un oggetto JSON")
        }
        let output = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: URL(fileURLWithPath: path), options: .atomic)
        return success([
            "title": "Write JSON \(path)",
            "path": path,
            "detail": "Patch applicata",
            "output": String(data: output, encoding: .utf8) ?? ""
        ], startDate: startDate)
    }

    private func executeWorkspaceStats(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let scope = (call.args["path"] ?? ".").trimmingCharacters(in: .whitespacesAndNewlines)
        let cmd = "printf \"files: \"; find '\(shellEscaped(scope))' -type f | wc -l; printf \"dirs: \"; find '\(shellEscaped(scope))' -type d | wc -l; printf \"bytes: \"; du -sk '\(shellEscaped(scope))' | awk '{print $1*1024}'"
        return await runBash(
            command: cmd,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Workspace stats",
            timeoutMs: context.policy.timeoutMs,
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )
    }

    private func executeDependencyAudit(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let manager = (call.args["manager"] ?? "swift").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let command: String
        switch manager {
        case "swift":
            command = "swift package show-dependencies --format text"
        case "npm", "node":
            command = "npm audit --json || true"
        case "pnpm":
            command = "pnpm audit --json || true"
        case "yarn":
            command = "yarn audit --json || true"
        default:
            return failure("manager non supportato: \(manager)", errorCode: "validation", startDate: startDate)
        }
        return await runBash(
            command: command,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Dependency audit",
            timeoutMs: context.policy.timeoutMs,
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )
    }

    private func executeTailLog(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let lines = max(1, min(2_000, Int(call.args["lines"] ?? "200") ?? 200))
        guard let rawPath = call.args["path"], !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return failure("path obbligatorio", errorCode: "validation", startDate: startDate)
        }
        do {
            let path = try resolveRequiredPath(rawPath, context: context)
            let cmd = "tail -n \(lines) '\(shellEscaped(path))'"
            return await runBash(
                command: cmd,
                cwd: context.workspaceContext.workspacePath,
                startDate: startDate,
                title: "Tail log",
                timeoutMs: context.policy.timeoutMs,
                maxOutputBytes: context.policy.maxBashOutputBytes,
                policy: context.policy
            )
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate)
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate)
        }
    }

    private func runBash(
        command: String,
        cwd: URL,
        startDate: Date,
        title: String,
        timeoutMs: Int,
        maxOutputBytes: Int,
        policy: ToolRuntimePolicy
    ) async -> ToolResult {
        do {
            try validateShell(command: command, policy: policy)
            let controller = self.executionController
            let scope = self.executionScope
            let result = try await withThrowingTaskGroup(
                of: (output: [String], terminationStatus: Int32).self
            ) { group in
                group.addTask {
                    try await ProcessRunner.runCollecting(
                        executable: "/bin/zsh",
                        arguments: ["-lc", command],
                        workingDirectory: cwd,
                        executionController: controller,
                        scope: scope
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(max(1_000, timeoutMs)) * 1_000_000)
                    controller?.terminate(scope: scope)
                    throw ToolRuntimeError.timeout(tool: "bash", ms: timeoutMs)
                }
                guard let first = try await group.next() else {
                    throw ToolRuntimeError.transport("Nessuna risposta dal processo")
                }
                group.cancelAll()
                return first
            }

            let output = truncate(result.output.joined(separator: "\n"), maxBytes: maxOutputBytes)
            if result.terminationStatus == 0 {
                return success([
                    "title": title,
                    "command": command,
                    "cwd": cwd.path,
                    "output": output
                ], startDate: startDate)
            }
            return failure(
                "exit \(result.terminationStatus): \(truncate(output, maxBytes: 3_000))",
                errorCode: "transport",
                startDate: startDate,
                payload: [
                    "title": title,
                    "command": command,
                    "cwd": cwd.path,
                    "output": output
                ]
            )
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: [
                "title": title,
                "command": command,
                "cwd": cwd.path,
                "timeout_ms": "\(timeoutMs)"
            ])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: [
                "title": title,
                "command": command,
                "cwd": cwd.path
            ])
        }
    }

    // MARK: - Web Search

    private func executeWebSearch(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let query = (call.args["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return failure("query is required", errorCode: "validation", startDate: startDate)
        }

        do {
            let results = try await webSearch.search(query: query, maxResults: 10)
            if results.isEmpty {
                return success([
                    "title": "Web search: \(query)",
                    "query": query,
                    "detail": "No results found",
                    "output": "[]",
                    "resultCount": "0"
                ], startDate: startDate)
            }

            let jsonArray: [[String: String]] = results.map { result in
                ["title": result.title, "snippet": result.snippet, "url": result.url]
            }
            let jsonData = try JSONSerialization.data(withJSONObject: jsonArray, options: [.prettyPrinted, .sortedKeys])
            let output = String(data: jsonData, encoding: .utf8) ?? "[]"

            return success([
                "title": "Web search: \(query)",
                "query": query,
                "detail": "\(results.count) results",
                "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
                "resultCount": "\(results.count)"
            ], startDate: startDate)
        } catch {
            return failure(
                "Web search failed: \(error.localizedDescription)",
                errorCode: "transport",
                startDate: startDate,
                payload: ["query": query, "title": "Web search failed"]
            )
        }
    }

    // MARK: - Web Fetch

    private func executeWebFetch(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let urlString = (call.args["url"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else {
            return failure("url is required", errorCode: "validation", startDate: startDate)
        }

        do {
            let markdown = try await webFetch.fetch(urlString: urlString)
            return success([
                "title": "Fetched: \(urlString)",
                "url": urlString,
                "detail": "\(markdown.count) chars",
                "output": truncate(markdown, maxBytes: context.policy.maxBashOutputBytes)
            ], startDate: startDate)
        } catch {
            return failure(
                "Web fetch failed: \(error.localizedDescription)",
                errorCode: "transport",
                startDate: startDate,
                payload: ["url": urlString, "title": "Web fetch failed"]
            )
        }
    }

    private func validate(call: ToolCall, normalizedName: String) throws {
        switch normalizedName {
        case "read", "write", "edit", "read_range", "list_dir", "read_json", "write_json", "tail_log",
             "str_replace", "create_file":
            let path = call.args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if path.isEmpty && normalizedName != "list_dir" {
                throw ToolRuntimeError.validation("path is required")
            }
        case "grep", "web_search", "search_symbols", "codebase_search", "find_symbol", "find_references",
             "rename_symbol", "semantic_search":
            let query = call.args["query"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if query.isEmpty {
                throw ToolRuntimeError.validation("query is required")
            }
        case "web_fetch":
            let url = call.args["url"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if url.isEmpty {
                throw ToolRuntimeError.validation("url is required")
            }
        case "list_symbols", "file_outline", "dependency_graph":
            let path = call.args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if path.isEmpty {
                throw ToolRuntimeError.validation("path is required")
            }
        case "bash":
            let command = call.args["command"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if command.isEmpty {
                throw ToolRuntimeError.validation("command is required")
            }
        case "mcp_reconnect":
            let server = (call.args["server"] ?? call.args["server_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if server.isEmpty {
                throw ToolRuntimeError.validation("server is required")
            }
        default:
            break
        }
    }

    private func resolveRequiredPath(_ rawPath: String?, context: ToolExecutionContext) throws -> String {
        guard let path = resolvePath(rawPath, workspace: context.workspaceContext.workspacePath.path, sandboxMode: context.policy.sandboxMode) else {
            throw ToolRuntimeError.sandboxViolation("Path non consentito dal sandbox")
        }
        return path
    }

    private func resolvePath(_ rawPath: String?, workspace: String, sandboxMode: String) -> String? {
        let raw = (rawPath ?? ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let workspaceURL = URL(fileURLWithPath: workspace).standardizedFileURL
        let resolvedURL: URL
        if (raw as NSString).isAbsolutePath {
            resolvedURL = URL(fileURLWithPath: raw).standardizedFileURL
        } else {
            resolvedURL = workspaceURL.appendingPathComponent(raw).standardizedFileURL
        }

        if sandboxMode != "danger-full-access" {
            let workspacePath = workspaceURL.path.hasSuffix("/") ? workspaceURL.path : workspaceURL.path + "/"
            let resolvedPath = resolvedURL.path
            if resolvedPath != workspaceURL.path && !resolvedPath.hasPrefix(workspacePath) {
                return nil
            }
        }
        return resolvedURL.path
    }

    private func validateShell(command: String, policy: ToolRuntimePolicy) throws {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ToolRuntimeError.validation("Comando vuoto")
        }
        let lower = trimmed.lowercased()

        if !policy.allowDangerousShellPatterns {
            let blockedPatterns = [
                "rm -rf /", ":(){ :|:& };:", "sudo ", "> /dev/sd", "mkfs", "dd if=", "shutdown", "reboot", "kill -9 1"
            ]
            for pattern in blockedPatterns where lower.contains(pattern) {
                throw ToolRuntimeError.sandboxViolation("Comando bloccato da policy strict")
            }

            if lower.contains(" > /") || lower.contains(" >> /") {
                throw ToolRuntimeError.sandboxViolation("Redirection assoluta bloccata in strict mode")
            }

            let head = lower.split(separator: " ").first.map(String.init) ?? ""
            let allowlist: Set<String> = [
                "rg", "find", "git", "ls", "cat", "head", "tail", "sed", "awk", "wc", "echo", "pwd", "stat", "which",
                "swift", "ps", "du", "printf", "npm", "pnpm", "yarn", "node", "python", "python3",
                "cargo", "rustc", "go", "make", "cmake", "mkdir", "cp", "mv", "touch", "chmod",
                "curl", "tar", "unzip", "zip", "diff", "sort", "uniq", "xargs", "tee", "env",
                "xcodebuild", "xcrun", "swiftformat", "swiftlint", "prettier", "eslint",
                "fd", "tree", "jq", "gh", "brew", "pip", "pip3", "pod", "bundle", "ruby",
                "docker", "docker-compose", "kubectl", "terraform", "deno", "bun",
                "test", "[", "true", "false", "date", "basename", "dirname", "realpath", "readlink",
                "grep", "egrep", "fgrep", "tr", "cut", "paste", "column", "comm", "join",
            ]
            if !head.isEmpty && !allowlist.contains(head) {
                throw ToolRuntimeError.sandboxViolation("Comando non consentito in strict mode: \(head)")
            }
        }
    }

    private func buildBasePayload(call: ToolCall, normalizedName: String) -> [String: String] {
        var payload: [String: String] = [
            "tool_call_id": call.id,
            "tool": normalizedName,
            "status": "started"
        ]
        if let command = call.args["command"], !command.isEmpty {
            payload["command"] = command
            payload["title"] = "Bash"
            payload["detail"] = command
        }
        if let cwd = call.args["cwd"], !cwd.isEmpty {
            payload["cwd"] = cwd
        }
        if let query = call.args["query"], !query.isEmpty {
            payload["query"] = query
        }
        if let url = call.args["url"], !url.isEmpty {
            payload["url"] = url
        }
        if let server = call.args["server"] ?? call.args["server_id"], !server.isEmpty {
            payload["server_id"] = server
            payload["mcp_server"] = server
        }
        if let swarmId = call.swarmId, !swarmId.isEmpty {
            payload["swarm_id"] = swarmId
            payload["group_id"] = "swarm-\(swarmId)"
        }
        return payload
    }

    private func eventTypeForTool(name: String, ok: Bool) -> String {
        switch name {
        case "read", "glob", "grep", "read_range", "list_dir", "git_diff", "search_symbols",
             "run_tests", "build_project", "list_processes", "read_json", "write_json",
             "workspace_stats", "dependency_audit", "tail_log",
             "codebase_search", "find_symbol", "list_symbols", "find_references",
             "project_structure", "file_outline", "find_files", "codebase_stats",
             "dependency_graph", "list_types", "list_tests", "index_status", "reindex",
             "diagnostics", "attempt_completion",
             "debug_log", "debug_query", "debug_session", "debug_hypothesize",
             "debug_mark", "debug_clean", "run_single_test",
             "semantic_search", "read_lints", "debug_context":
            return ok ? "read_batch_completed" : "tool_execution_error"
        case "edit", "write", "str_replace", "create_file", "parallel_apply", "regex_replace",
             "rename_symbol", "find_and_replace_all", "undo_edit":
            return ok ? "file_change" : "tool_execution_error"
        case "bash":
            return ok ? "command_execution" : "tool_execution_error"
        case "web_search":
            return ok ? "web_search_completed" : "web_search_failed"
        case "web_fetch":
            return ok ? "web_fetch_completed" : "web_fetch_failed"
        default:
            return ok ? "mcp_tool_call" : "tool_execution_error"
        }
    }

    private func normalizeToolName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func shellEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    private func truncate(_ input: String, maxBytes: Int) -> String {
        let data = input.data(using: .utf8) ?? Data()
        if data.count <= maxBytes { return input }
        let prefixData = data.prefix(maxBytes)
        let prefixText = String(data: prefixData, encoding: .utf8) ?? String(input.prefix(maxBytes / 2))
        return prefixText + "\n...[truncated]"
    }

    private func success(_ payload: [String: String], startDate: Date) -> ToolResult {
        ToolResult(ok: true, payload: payload, durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000)))
    }

    private func failure(
        _ message: String,
        errorCode: String,
        startDate: Date,
        payload: [String: String] = [:]
    ) -> ToolResult {
        var p = payload
        p["title"] = p["title"] ?? "Tool error"
        p["detail"] = message
        p["stderr"] = message
        p["error_code"] = errorCode
        return ToolResult(ok: false, payload: p, durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000)))
    }

    private func buildDiffPreview(old: String, new: String) -> String {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        let maxCount = min(max(oldLines.count, newLines.count), 80)
        for i in 0..<maxCount {
            let oldLine = i < oldLines.count ? oldLines[i] : nil
            let newLine = i < newLines.count ? newLines[i] : nil
            if oldLine == newLine { continue }
            if let oldLine {
                out.append("- \(oldLine)")
            }
            if let newLine {
                out.append("+ \(newLine)")
            }
            if out.count >= 40 { break }
        }
        return out.joined(separator: "\n")
    }

    private func parseJSONObject(from raw: String) throws -> Any {
        guard let data = raw.data(using: .utf8) else {
            throw ToolRuntimeError.validation("JSON patch non valido")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - Codebase Index Tool Execution

    private func executeIndexTool(
        name: String,
        call: ToolCall,
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult {
        guard let indexTools else {
            return failure(
                "Codebase index not available. Run 'reindex' or open a workspace first.",
                errorCode: "validation",
                startDate: startDate
            )
        }
        let events = await indexTools.execute(
            toolName: name,
            args: call.args,
            callId: call.id,
            workspacePaths: workspacePaths,
            excludedPaths: excludedPaths
        )
        return toolResultFromIndexEvents(events, startDate: startDate)
    }

    private func toolResultFromIndexEvents(_ events: [StreamEvent], startDate: Date) -> ToolResult {
        for event in events {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "tool_execution_error" || payload["status"] == "failed" {
                return failure(
                    payload["detail"] ?? payload["output"] ?? "Index tool failed",
                    errorCode: "transport",
                    startDate: startDate,
                    payload: payload
                )
            }
            if payload["status"] == "completed" {
                return ToolResult(
                    ok: true,
                    payload: payload,
                    durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000))
                )
            }
        }
        return failure("No result from index tool", errorCode: "transport", startDate: startDate)
    }

    // MARK: - Improved Grep

    private func executeGrep(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let query = call.args["query"] ?? ""
        let scope = call.args["pathScope"] ?? call.args["path"] ?? "."
        let fileType = call.args["fileType"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let contextLines = Int(call.args["context_lines"] ?? "") ?? 2
        let caseSensitive = (call.args["case_sensitive"] ?? "false").lowercased() == "true"
        let multiline = (call.args["multiline"] ?? "false").lowercased() == "true"

        // If query looks like a symbol name (no regex chars) and index is available, try index first
        if let indexTools, !query.isEmpty, !containsRegexChars(query) {
            let indexEvents = await indexTools.execute(
                toolName: "codebase_search",
                args: ["query": query, "kind": "all"],
                callId: call.id,
                workspacePaths: workspacePaths,
                excludedPaths: excludedPaths
            )
            let indexResult = toolResultFromIndexEvents(indexEvents, startDate: startDate)
            if indexResult.ok,
               let output = indexResult.payload["output"],
               !output.isEmpty,
               !output.contains("No symbols found") {
                // Merge with ripgrep results for completeness
                var payload = indexResult.payload
                payload["title"] = "Grep \(query) (index + rg)"
                return ToolResult(ok: true, payload: payload, durationMs: indexResult.durationMs)
            }
        }

        // Full ripgrep search
        var cmd = "rg -n --no-heading --max-count 200"
        if !caseSensitive { cmd += " -i" }
        if multiline { cmd += " -U" }
        if !fileType.isEmpty { cmd += " --type '\(shellEscaped(fileType))'" }
        if contextLines > 0 { cmd += " -C \(min(contextLines, 10))" }
        cmd += " '\(shellEscaped(query))' '\(shellEscaped(scope))' | head -n 500"

        let rawResult = await runBash(
            command: cmd,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Grep \(query)",
            timeoutMs: context.policy.timeoutMs,
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )

        // Post-process: rank results by file importance
        if rawResult.ok, let output = rawResult.payload["output"], !output.isEmpty {
            let ranked = rankGrepResults(output, query: query)
            var payload = rawResult.payload
            payload["output"] = ranked
            return ToolResult(ok: true, payload: payload, durationMs: rawResult.durationMs)
        }
        return rawResult
    }

    private func containsRegexChars(_ s: String) -> Bool {
        let regexSpecial = CharacterSet(charactersIn: ".*+?[](){}^$|\\")
        return s.unicodeScalars.contains { regexSpecial.contains($0) }
    }

    private func rankGrepResults(_ output: String, query: String) -> String {
        let lines = output.components(separatedBy: "\n")
        guard lines.count > 5 else { return output }

        // Group results by file
        struct FileResults {
            var path: String
            var lines: [String]
            var score: Int
        }

        var fileGroups: [String: [String]] = [:]
        var currentFile: String?

        for line in lines {
            if line.contains(":") && !line.hasPrefix("-") && !line.hasPrefix(" ") {
                let parts = line.split(separator: ":", maxSplits: 2)
                if parts.count >= 2, let _ = Int(parts[1]) {
                    currentFile = String(parts[0])
                }
            }
            if let file = currentFile {
                fileGroups[file, default: []].append(line)
            }
        }

        if fileGroups.isEmpty { return output }

        // Score files: source files > config > docs, shorter paths > deeper
        let sourceExts: Set<String> = ["swift", "ts", "tsx", "js", "jsx", "py", "go", "rs", "java", "kt", "rb"]
        let scored = fileGroups.map { (path, resultLines) -> FileResults in
            var score = 0
            let ext = (path as NSString).pathExtension.lowercased()
            if sourceExts.contains(ext) { score += 100 }
            let depth = path.components(separatedBy: "/").count
            score += max(0, 20 - depth * 2)
            // Exact match bonus
            if resultLines.contains(where: { $0.lowercased().contains(query.lowercased()) }) {
                score += 50
            }
            return FileResults(path: path, lines: resultLines, score: score)
        }.sorted { $0.score > $1.score }

        return scored.flatMap(\.lines).joined(separator: "\n")
    }

    // MARK: - Improved Glob

    private func executeGlob(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let pattern = call.args["pattern"] ?? "*"
        let scopePath = call.args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "."

        // Try index-powered file finder first for fuzzy name matching
        if let indexTools, !pattern.contains("*") {
            let indexEvents = await indexTools.execute(
                toolName: "find_files",
                args: ["query": pattern],
                callId: call.id,
                workspacePaths: workspacePaths,
                excludedPaths: excludedPaths
            )
            let indexResult = toolResultFromIndexEvents(indexEvents, startDate: startDate)
            if indexResult.ok,
               let output = indexResult.payload["output"],
               !output.isEmpty,
               !output.contains("No files found") {
                var payload = indexResult.payload
                payload["title"] = "Glob \(pattern) (index)"
                return ToolResult(ok: true, payload: payload, durationMs: indexResult.durationMs)
            }
        }

        // Fallback to ripgrep file search
        let cmd = "rg --files -g '\(shellEscaped(pattern))' '\(shellEscaped(scopePath))' 2>/dev/null | head -n 500"
        return await runBash(
            command: cmd,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Glob \(pattern)",
            timeoutMs: context.policy.timeoutMs,
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )
    }

    // MARK: - New Tool: parallel_apply (multi-edit)

    private func executeParallelApply(call: ToolCall, context: ToolExecutionContext, startDate: Date) async throws -> ToolResult {
        guard let editsRaw = call.args["edits"], !editsRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolRuntimeError.validation("edits (JSON array) is required for parallel_apply")
        }
        guard let editsData = editsRaw.data(using: .utf8),
              let editsArray = try? JSONSerialization.jsonObject(with: editsData) as? [[String: String]] else {
            throw ToolRuntimeError.validation("edits must be a JSON array of objects with path, old_string, new_string")
        }
        guard !editsArray.isEmpty else {
            throw ToolRuntimeError.validation("edits array is empty")
        }

        var results: [(path: String, ok: Bool, detail: String)] = []
        for edit in editsArray {
            let editCall = ToolCall(
                id: UUID().uuidString,
                name: "str_replace",
                args: edit,
                sourceProvider: call.sourceProvider,
                swarmId: call.swarmId,
                scope: call.scope
            )
            do {
                let result = try executeStrReplace(call: editCall, context: context, startDate: Date())
                results.append((
                    path: edit["path"] ?? "?",
                    ok: result.ok,
                    detail: result.payload["detail"] ?? (result.ok ? "ok" : "failed")
                ))
            } catch {
                results.append((path: edit["path"] ?? "?", ok: false, detail: error.localizedDescription))
            }
        }

        let summary = results.map { "\($0.ok ? "OK" : "FAIL") \($0.path): \($0.detail)" }.joined(separator: "\n")
        let allOk = results.allSatisfy(\.ok)
        let successCount = results.filter(\.ok).count
        return ToolResult(
            ok: allOk,
            payload: [
                "title": "parallel_apply (\(results.count) edits)",
                "output": summary,
                "detail": "\(successCount)/\(results.count) edits succeeded"
            ],
            durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000))
        )
    }

    // MARK: - New Tool: regex_replace

    private func executeRegexReplace(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        guard let pathArg = call.args["path"] else {
            throw ToolRuntimeError.validation("path is required")
        }
        let path = try resolveRequiredPath(pathArg, context: context)
        guard FileManager.default.fileExists(atPath: path) else {
            throw ToolRuntimeError.validation("File not found: \(path)")
        }

        let pattern = call.args["pattern"] ?? ""
        let replacement = call.args["replacement"] ?? ""
        guard !pattern.isEmpty else {
            throw ToolRuntimeError.validation("pattern (regex) is required")
        }

        let flags = call.args["flags"] ?? ""
        var options: NSRegularExpression.Options = []
        if flags.contains("i") { options.insert(.caseInsensitive) }
        if flags.contains("m") { options.insert(.anchorsMatchLines) }
        if flags.contains("s") { options.insert(.dotMatchesLineSeparators) }

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw ToolRuntimeError.validation("Invalid regex pattern: \(error.localizedDescription)")
        }

        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let range = NSRange(content.startIndex..., in: content)
        let matchCount = regex.numberOfMatches(in: content, range: range)

        guard matchCount > 0 else {
            return success([
                "title": "regex_replace (0 matches)",
                "path": path,
                "detail": "Pattern '\(pattern)' not found in \(path)"
            ], startDate: startDate)
        }

        let newContent = regex.stringByReplacingMatches(in: content, range: range, withTemplate: replacement)
        try newContent.write(toFile: path, atomically: true, encoding: .utf8)

        return success([
            "title": "regex_replace \((path as NSString).lastPathComponent)",
            "path": path,
            "file": path,
            "detail": "Replaced \(matchCount) match(es) of /\(pattern)/\(flags)"
        ], startDate: startDate)
    }

    // MARK: - New Tool: attempt_completion

    private func executeAttemptCompletion(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let result = call.args["result"] ?? "Task completed"
        let command = call.args["command"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !command.isEmpty {
            // Run verification command
            let verifyResult = await runBash(
                command: command,
                cwd: context.workspaceContext.workspacePath,
                startDate: startDate,
                title: "Verification",
                timeoutMs: context.policy.timeoutMs,
                maxOutputBytes: context.policy.maxBashOutputBytes,
                policy: context.policy
            )
            if !verifyResult.ok {
                let output = verifyResult.payload["output"] ?? ""
                return failure(
                    "Verification failed: \(truncate(output, maxBytes: 2000))",
                    errorCode: "transport",
                    startDate: startDate,
                    payload: [
                        "title": "attempt_completion (verification failed)",
                        "command": command,
                        "output": output
                    ]
                )
            }
        }

        return success([
            "title": "Task completed",
            "output": result,
            "detail": command.isEmpty ? "Completion signaled" : "Verified with: \(command)"
        ], startDate: startDate)
    }

    // MARK: - New Tool: diagnostics

    private func executeDiagnostics(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let manager = (call.args["manager"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Auto-detect project type if not specified
        let buildCommand: String
        let projectType: String
        if !manager.isEmpty {
            switch manager {
            case "swift": buildCommand = "swift build 2>&1"; projectType = "Swift"
            case "npm": buildCommand = "npm run build 2>&1 || true"; projectType = "Node/npm"
            case "cargo": buildCommand = "cargo check 2>&1"; projectType = "Rust/Cargo"
            case "go": buildCommand = "go build ./... 2>&1"; projectType = "Go"
            default: buildCommand = "swift build 2>&1"; projectType = manager
            }
        } else {
            // Auto-detect
            let wsPath = context.workspaceContext.workspacePath.path
            if FileManager.default.fileExists(atPath: (wsPath as NSString).appendingPathComponent("Package.swift")) {
                buildCommand = "swift build 2>&1"
                projectType = "Swift"
            } else if FileManager.default.fileExists(atPath: (wsPath as NSString).appendingPathComponent("package.json")) {
                buildCommand = "npm run build 2>&1 || true"
                projectType = "Node/npm"
            } else if FileManager.default.fileExists(atPath: (wsPath as NSString).appendingPathComponent("Cargo.toml")) {
                buildCommand = "cargo check 2>&1"
                projectType = "Rust/Cargo"
            } else if FileManager.default.fileExists(atPath: (wsPath as NSString).appendingPathComponent("go.mod")) {
                buildCommand = "go build ./... 2>&1"
                projectType = "Go"
            } else {
                buildCommand = "swift build 2>&1"
                projectType = "Swift (default)"
            }
        }

        let buildResult = await runBash(
            command: buildCommand,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Diagnostics",
            timeoutMs: max(context.policy.timeoutMs, 120_000),
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )

        let rawOutput = buildResult.payload["output"] ?? ""

        // Parse diagnostics from output
        var errors: [(file: String, line: String, col: String, severity: String, message: String)] = []
        let diagnosticPattern = try? NSRegularExpression(pattern: #"^(.+?):(\d+):(\d+):\s*(error|warning|note):\s*(.+)$"#, options: .anchorsMatchLines)

        if let regex = diagnosticPattern {
            let matches = regex.matches(in: rawOutput, range: NSRange(rawOutput.startIndex..., in: rawOutput))
            for match in matches.prefix(100) {
                guard match.numberOfRanges >= 6 else { continue }
                func extract(_ i: Int) -> String {
                    guard let r = Range(match.range(at: i), in: rawOutput) else { return "" }
                    return String(rawOutput[r])
                }
                errors.append((file: extract(1), line: extract(2), col: extract(3), severity: extract(4), message: extract(5)))
            }
        }

        let errorCount = errors.filter { $0.severity == "error" }.count
        let warningCount = errors.filter { $0.severity == "warning" }.count

        var output = "Project: \(projectType)\n"
        output += "Status: \(buildResult.ok ? "BUILD SUCCESS" : "BUILD FAILED")\n"
        output += "Errors: \(errorCount), Warnings: \(warningCount)\n\n"

        if !errors.isEmpty {
            for diag in errors.prefix(50) {
                let icon = diag.severity == "error" ? "ERROR" : diag.severity == "warning" ? "WARN" : "NOTE"
                output += "[\(icon)] \(diag.file):\(diag.line):\(diag.col) \(diag.message)\n"
            }
            if errors.count > 50 {
                output += "... and \(errors.count - 50) more diagnostics\n"
            }
        } else if !buildResult.ok {
            output += rawOutput
        }

        return ToolResult(
            ok: true,
            payload: [
                "title": "Diagnostics (\(projectType))",
                "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
                "detail": buildResult.ok ? "Build OK" : "\(errorCount) errors, \(warningCount) warnings"
            ],
            durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000))
        )
    }

    private func prettyJSON(_ obj: Any) -> String {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return String(describing: obj)
        }
        return text
    }

    private func parseEmbeddedArgs(_ raw: String?) -> [String: String] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        var out: [String: String] = [:]
        for (k, v) in json {
            if let s = v as? String {
                out[k] = s
            } else if let b = v as? Bool {
                out[k] = b ? "true" : "false"
            } else if let n = v as? NSNumber {
                out[k] = n.stringValue
            } else if let serialized = try? JSONSerialization.data(withJSONObject: v),
                      let str = String(data: serialized, encoding: .utf8)
            {
                out[k] = str
            } else {
                out[k] = String(describing: v)
            }
        }
        return out
    }

    // MARK: - New Powerful Tools

    private func executeRenameSymbol(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let query = call.args["query"] ?? ""
        let newName = call.args["new_name"] ?? ""
        guard !query.isEmpty, !newName.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "Both query and new_name are required"], durationMs: 0)
        }
        let workspace = context.workspaceContext.workspacePath.path

        // Use index to find all references
        var files: [(path: String, line: Int, content: String)] = []
        if indexTools != nil {
            let refCall = ToolCall(id: UUID().uuidString, name: "find_references", args: ["query": query], sourceProvider: call.sourceProvider, swarmId: nil, scope: call.scope)
            let refResult = await executeIndexTool(name: "find_references", call: refCall, context: context, startDate: startDate)
            if refResult.ok, let output = refResult.payload["output"] {
                // Parse references output
                for line in output.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { continue }
                    // Format: "file.swift:42: content..."
                    let parts = trimmed.components(separatedBy: ":")
                    if parts.count >= 2, let lineNum = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                        let filePath = parts[0].trimmingCharacters(in: .whitespaces)
                        let absPath = (filePath as NSString).isAbsolutePath ? filePath : (workspace as NSString).appendingPathComponent(filePath)
                        files.append((path: absPath, line: lineNum, content: trimmed))
                    }
                }
            }
        }

        // Fallback to ripgrep if no index results
        if files.isEmpty {
            let rgArgs = ["-rn", "--no-heading", query, workspace]
            let (output, _, _) = await shellExec(args: ["/usr/bin/rg"] + rgArgs, cwd: workspace, timeout: 15_000)
            for line in output.components(separatedBy: "\n") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 3, let lineNum = Int(parts[1]) {
                    files.append((path: parts[0], line: lineNum, content: line))
                }
            }
        }

        guard !files.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "Symbol '\(query)' not found in codebase"], durationMs: Int(Date().timeIntervalSince(startDate) * 1000))
        }

        // Get unique file paths and perform replacements
        let uniquePaths = Set(files.map(\.path))
        var replaced = 0
        var errors: [String] = []

        for filePath in uniquePaths {
            guard FileManager.default.fileExists(atPath: filePath) else { continue }
            do {
                var content = try String(contentsOfFile: filePath, encoding: .utf8)
                let originalContent = content
                content = content.replacingOccurrences(of: query, with: newName)
                if content != originalContent {
                    try content.write(toFile: filePath, atomically: true, encoding: .utf8)
                    replaced += 1
                }
            } catch {
                errors.append("\(filePath): \(error.localizedDescription)")
            }
        }

        let detail = "Renamed '\(query)' → '\(newName)' in \(replaced) files (\(files.count) references)"
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: errors.isEmpty, payload: [
            "title": "rename_symbol",
            "detail": errors.isEmpty ? detail : "\(detail); errors: \(errors.joined(separator: "; "))",
            "output": detail
        ], durationMs: ms)
    }

    private func executeFindAndReplaceAll(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let pattern = call.args["pattern"] ?? call.args["query"] ?? ""
        let replacement = call.args["replacement"] ?? call.args["new_string"] ?? ""
        let fileType = call.args["file_type"] ?? call.args["fileType"] ?? ""
        let isRegex = (call.args["regex"] ?? "false").lowercased() == "true"
        let workspace = context.workspaceContext.workspacePath.path

        guard !pattern.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "pattern is required"], durationMs: 0)
        }

        // Use ripgrep to find matching files
        var rgArgs = ["-l", "--no-heading"]
        if !fileType.isEmpty { rgArgs += ["-t", fileType] }
        rgArgs.append(pattern)
        rgArgs.append(workspace)

        let (output, _, _) = await shellExec(args: ["/usr/bin/rg"] + rgArgs, cwd: workspace, timeout: 15_000)
        let matchingFiles = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        guard !matchingFiles.isEmpty else {
            return ToolResult(ok: true, payload: ["detail": "No matches found for '\(pattern)'", "output": "0 files changed"], durationMs: Int(Date().timeIntervalSince(startDate) * 1000))
        }

        var totalReplacements = 0
        var errors: [String] = []

        for filePath in matchingFiles {
            do {
                var content = try String(contentsOfFile: filePath, encoding: .utf8)
                let original = content
                if isRegex {
                    let regex = try NSRegularExpression(pattern: pattern)
                    content = regex.stringByReplacingMatches(in: content, range: NSRange(content.startIndex..., in: content), withTemplate: replacement)
                } else {
                    content = content.replacingOccurrences(of: pattern, with: replacement)
                }
                if content != original {
                    try content.write(toFile: filePath, atomically: true, encoding: String.Encoding.utf8)
                    totalReplacements += 1
                }
            } catch {
                errors.append("\((filePath as NSString).lastPathComponent): \(error.localizedDescription)")
            }
        }

        let detail = "Replaced '\(pattern)' → '\(replacement)' in \(totalReplacements)/\(matchingFiles.count) files"
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: errors.isEmpty, payload: [
            "title": "find_and_replace_all",
            "detail": errors.isEmpty ? detail : "\(detail); errors: \(errors.prefix(5).joined(separator: "; "))",
            "output": detail
        ], durationMs: ms)
    }

    private func executeUndoEdit(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let rawPath = call.args["path"] ?? ""
        guard !rawPath.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "path is required"], durationMs: 0)
        }
        let workspace = context.workspaceContext.workspacePath.path
        let path: String
        if (rawPath as NSString).isAbsolutePath {
            path = rawPath
        } else {
            path = (workspace as NSString).appendingPathComponent(rawPath)
        }

        // git checkout -- <file> to revert to last committed state
        let (output, stderr, exitCode) = await shellExec(args: ["/usr/bin/git", "checkout", "--", path], cwd: workspace, timeout: 10_000)
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        if exitCode == 0 {
            return ToolResult(ok: true, payload: [
                "title": "undo_edit",
                "detail": "Reverted \((path as NSString).lastPathComponent) to last committed state",
                "path": path,
                "output": output.isEmpty ? "File reverted successfully" : output
            ], durationMs: ms)
        } else {
            return ToolResult(ok: false, payload: [
                "title": "undo_edit",
                "detail": "Failed to revert: \(stderr.isEmpty ? output : stderr)",
                "path": path
            ], durationMs: ms)
        }
    }

    private func executeRunSingleTest(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let testName = call.args["test"] ?? call.args["name"] ?? call.args["filter"] ?? ""
        let target = call.args["target"] ?? ""
        let workspace = context.workspaceContext.workspacePath.path

        guard !testName.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "test name/filter is required"], durationMs: 0)
        }

        // Detect project type and build command
        let fm = FileManager.default
        var cmd: [String]
        if fm.fileExists(atPath: (workspace as NSString).appendingPathComponent("Package.swift")) {
            cmd = ["/usr/bin/swift", "test", "--filter", testName]
            if !target.isEmpty { cmd += ["--target", target] }
        } else if fm.fileExists(atPath: (workspace as NSString).appendingPathComponent("package.json")) {
            cmd = ["/usr/bin/env", "npx", "jest", "--testPathPattern", testName, "--no-coverage"]
        } else if fm.fileExists(atPath: (workspace as NSString).appendingPathComponent("Cargo.toml")) {
            cmd = ["/usr/bin/env", "cargo", "test", testName, "--", "--nocapture"]
        } else if fm.fileExists(atPath: (workspace as NSString).appendingPathComponent("go.mod")) {
            cmd = ["/usr/bin/env", "go", "test", "-run", testName, "-v", "./..."]
        } else {
            cmd = ["/usr/bin/swift", "test", "--filter", testName]
        }

        let (output, stderr, exitCode) = await shellExec(args: cmd, cwd: workspace, timeout: 120_000)
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        let combined = (output + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines)

        // Also log to debug server
        await debugLogServer.logTestOutput(combined, source: "run_single_test:\(testName)")

        if exitCode == 0 {
            return ToolResult(ok: true, payload: [
                "title": "run_single_test",
                "detail": "Test '\(testName)' passed",
                "output": String(combined.suffix(8000))
            ], durationMs: ms)
        } else {
            return ToolResult(ok: false, payload: [
                "title": "run_single_test",
                "detail": "Test '\(testName)' failed (exit \(exitCode))",
                "output": String(combined.suffix(8000))
            ], durationMs: ms)
        }
    }

    // MARK: - Debug Tools

    private func executeDebugLog(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let severity = call.args["severity"] ?? "info"
        let source = call.args["source"] ?? "agent"
        let message = call.args["message"] ?? ""
        let detail = call.args["detail"]
        let category = call.args["category"]

        guard !message.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "message is required"], durationMs: 0)
        }

        await debugLogServer.log(severity: severity, source: source, message: message, detail: detail, category: category)

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: true, payload: [
            "title": "debug_log",
            "detail": "[\(severity.uppercased())] \(message)",
            "output": "Logged: [\(severity)] \(source): \(message)"
        ], durationMs: ms)
    }

    private func executeDebugQuery(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let severity = call.args["severity"]
        let category = call.args["category"]
        let search = call.args["search"] ?? call.args["query"]
        let limitStr = call.args["limit"] ?? "50"
        let limit = Int(limitStr) ?? 50
        let format = call.args["format"] ?? "summary" // summary or full

        if format == "summary" {
            let summary = await debugLogServer.sessionSummary()
            let ms = Int(Date().timeIntervalSince(startDate) * 1000)
            return ToolResult(ok: true, payload: [
                "title": "debug_query",
                "detail": "Debug session summary",
                "output": summary
            ], durationMs: ms)
        }

        let result = await debugLogServer.query(severity: severity, category: category, search: search, limit: limit)
        let formatted = await debugLogServer.recentFormatted(limit: limit)
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: true, payload: [
            "title": "debug_query",
            "detail": "\(result.totalCount) entries (\(result.errorCount) errors, \(result.warningCount) warnings)",
            "output": formatted
        ], durationMs: ms)
    }

    private func executeDebugSession(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let action = call.args["action"] ?? "start"
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)

        switch action {
        case "start":
            let sessionId = await debugLogServer.startSession()
            return ToolResult(ok: true, payload: [
                "title": "debug_session",
                "detail": "Debug session started (id: \(sessionId.prefix(8)))",
                "output": "Session \(sessionId) started"
            ], durationMs: ms)
        case "end", "stop":
            await debugLogServer.endSession()
            let summary = await debugLogServer.sessionSummary()
            return ToolResult(ok: true, payload: [
                "title": "debug_session",
                "detail": "Debug session ended",
                "output": summary
            ], durationMs: ms)
        case "clear":
            await debugLogServer.clearSession()
            return ToolResult(ok: true, payload: [
                "title": "debug_session",
                "detail": "Session logs cleared",
                "output": "Session logs cleared"
            ], durationMs: ms)
        default:
            return ToolResult(ok: false, payload: ["detail": "Unknown action: \(action). Use start, end, or clear."], durationMs: ms)
        }
    }

    private func executeDebugHypothesize(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let title = call.args["title"] ?? ""
        let description = call.args["description"] ?? ""
        let action = call.args["action"] ?? "propose" // propose, update
        let hypothesisId = call.args["hypothesis_id"]
        let status = call.args["status"]
        let evidence = call.args["evidence"]

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)

        switch action {
        case "propose":
            guard !title.isEmpty else {
                return ToolResult(ok: false, payload: ["detail": "title is required for new hypothesis"], durationMs: ms)
            }
            // Log the hypothesis to the debug server
            await debugLogServer.log(
                severity: "info",
                source: "hypothesis",
                message: "Hypothesis: \(title)",
                detail: description,
                category: "debug"
            )
            return ToolResult(ok: true, payload: [
                "title": "debug_hypothesize",
                "detail": "Hypothesis proposed: \(title)",
                "output": "Proposed hypothesis: \(title)\n\(description)"
            ], durationMs: ms)
        case "update":
            guard let hid = hypothesisId, !hid.isEmpty else {
                return ToolResult(ok: false, payload: ["detail": "hypothesis_id is required for update"], durationMs: ms)
            }
            let statusStr = status ?? "investigating"
            await debugLogServer.log(
                severity: "info",
                source: "hypothesis",
                message: "Hypothesis \(hid.prefix(8)) updated to \(statusStr)",
                detail: evidence,
                category: "debug"
            )
            return ToolResult(ok: true, payload: [
                "title": "debug_hypothesize",
                "detail": "Hypothesis updated to \(statusStr)",
                "output": "Updated hypothesis \(hid.prefix(8)) → \(statusStr)\(evidence.map { ". Evidence: \($0)" } ?? "")"
            ], durationMs: ms)
        default:
            return ToolResult(ok: false, payload: ["detail": "Unknown action: \(action). Use propose or update."], durationMs: ms)
        }
    }

    // MARK: - debug_mark: Insert a debug marker comment into a file

    private func executeDebugMark(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let rawPath = call.args["path"] ?? ""
        let lineStr = call.args["line"] ?? ""
        let comment = call.args["comment"] ?? "DEBUG"
        let code = call.args["code"] ?? ""
        let workspace = context.workspaceContext.workspacePath.path

        guard !rawPath.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "path is required"], durationMs: 0)
        }
        guard let lineNum = Int(lineStr), lineNum > 0 else {
            return ToolResult(ok: false, payload: ["detail": "valid line number is required"], durationMs: 0)
        }

        let path = (rawPath as NSString).isAbsolutePath ? rawPath : (workspace as NSString).appendingPathComponent(rawPath)
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)

        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            var lines = content.components(separatedBy: "\n")

            let insertIdx = min(lineNum, lines.count)
            let markerLine = code.isEmpty
                ? "// \u{1F41B} DEBUG: \(comment)"
                : code + " // \u{1F41B} DEBUG: \(comment)"

            lines.insert(markerLine, at: insertIdx)
            try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: String.Encoding.utf8)

            await debugLogServer.log(
                severity: "info",
                source: "debug_mark",
                message: "Marker inserted at \((path as NSString).lastPathComponent):\(lineNum)",
                detail: markerLine,
                category: "debug"
            )

            return ToolResult(ok: true, payload: [
                "title": "debug_mark",
                "detail": "Debug marker inserted at \((path as NSString).lastPathComponent):\(lineNum)",
                "output": "Inserted: \(markerLine)",
                "marker_info": "\(path)|\(lineNum)|\(comment)"
            ], durationMs: ms)
        } catch {
            return ToolResult(ok: false, payload: [
                "title": "debug_mark",
                "detail": "Failed to insert marker: \(error.localizedDescription)"
            ], durationMs: ms)
        }
    }

    // MARK: - debug_clean: Remove all debug markers from files

    private func executeDebugClean(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let rawPath = call.args["path"] ?? ""
        let workspace = context.workspaceContext.workspacePath.path
        let debugTag = "\u{1F41B} DEBUG:"
        var cleanedCount = 0
        var errors: [String] = []

        // If path is specified, clean only that file; otherwise search workspace
        let filesToClean: [String]
        if !rawPath.isEmpty {
            let path = (rawPath as NSString).isAbsolutePath ? rawPath : (workspace as NSString).appendingPathComponent(rawPath)
            filesToClean = [path]
        } else {
            // Use ripgrep to find all files with debug markers
            let (output, _, _) = await shellExec(args: ["/usr/bin/rg", "-l", "--no-heading", debugTag, workspace], cwd: workspace, timeout: 15_000)
            filesToClean = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        }

        for filePath in filesToClean {
            do {
                let content = try String(contentsOfFile: filePath, encoding: .utf8)
                let lines = content.components(separatedBy: "\n")
                let filtered = lines.filter { !$0.contains(debugTag) }

                if filtered.count < lines.count {
                    let removed = lines.count - filtered.count
                    try filtered.joined(separator: "\n").write(toFile: filePath, atomically: true, encoding: String.Encoding.utf8)
                    cleanedCount += removed
                }
            } catch {
                errors.append("\((filePath as NSString).lastPathComponent): \(error.localizedDescription)")
            }
        }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        let detail = "Removed \(cleanedCount) debug markers from \(filesToClean.count) files"

        await debugLogServer.log(severity: "info", source: "debug_clean", message: detail, category: "debug")

        return ToolResult(ok: errors.isEmpty, payload: [
            "title": "debug_clean",
            "detail": errors.isEmpty ? detail : "\(detail); errors: \(errors.prefix(3).joined(separator: "; "))",
            "output": detail
        ], durationMs: ms)
    }

    // MARK: - semantic_search: Search code by meaning using index + heuristic ranking

    private func executeSemanticSearch(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let query = (call.args["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return failure("query is required", errorCode: "validation", startDate: startDate)
        }
        let targetDirs = (call.args["target_directories"] ?? "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let numResults = min(max(Int(call.args["num_results"] ?? "25") ?? 25, 1), 50)
        let workspace = context.workspaceContext.workspacePath.path

        // Primary: BM25 SemanticIndex (AST-aware chunks + inverted index)
        if let index = codebaseIndex {
            let results = await index.semanticIndex.search(
                query: query,
                targetDirectories: targetDirs,
                numResults: numResults
            )

            if !results.isEmpty {
                var output = ""
                for (i, result) in results.enumerated() {
                    let chunk = result.chunk
                    let lineRange = chunk.startLine == chunk.endLine
                        ? ":\(chunk.startLine)"
                        : ":\(chunk.startLine)-\(chunk.endLine)"
                    let scopeInfo = chunk.scope.isEmpty ? "" : " [\(chunk.scope)]"
                    output += "\(i + 1). \(chunk.filePath)\(lineRange)\(scopeInfo) (score: \(String(format: "%.2f", result.score)))\n"

                    // Include a compact code preview (first 3 meaningful lines)
                    let previewLines = chunk.content
                        .components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .prefix(3)
                    for line in previewLines {
                        let trimmed = line.count > 120 ? String(line.prefix(120)) + "…" : line
                        output += "   \(trimmed)\n"
                    }
                }

                return success([
                    "title": "semantic_search",
                    "query": query,
                    "detail": "\(results.count) results (BM25 index)",
                    "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
                    "count": "\(results.count)"
                ], startDate: startDate)
            }
        }

        // Fallback: grep-based search when SemanticIndex is empty or unavailable
        let queryTokens = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        guard !queryTokens.isEmpty else {
            return success([
                "title": "semantic_search",
                "query": query,
                "detail": "No results found",
                "output": "No matches found for: \(query)",
                "count": "0"
            ], startDate: startDate)
        }

        // Generate grep patterns from query tokens (camelCase, snake_case, raw)
        var patterns: [String] = []
        if queryTokens.count >= 2 {
            patterns.append(queryTokens.joined(separator: ".*"))
            let camel = queryTokens[0] + queryTokens.dropFirst().map { $0.capitalized }.joined()
            patterns.append(camel)
            let pascal = queryTokens.map { $0.capitalized }.joined()
            patterns.append(pascal)
            patterns.append(queryTokens.joined(separator: "_"))
        }
        for token in queryTokens where token.count >= 3 {
            patterns.append(token)
        }

        struct FallbackResult: Comparable {
            let file: String; let line: Int; let snippet: String; let score: Double
            static func < (lhs: FallbackResult, rhs: FallbackResult) -> Bool { lhs.score > rhs.score }
        }

        var grepResults: [FallbackResult] = []
        for pattern in patterns.prefix(5) {
            let searchPath: String
            if let dir = targetDirs.first {
                searchPath = (dir as NSString).isAbsolutePath ? dir : (workspace as NSString).appendingPathComponent(dir)
            } else {
                searchPath = workspace
            }
            var grepArgs = ["/usr/bin/rg", "--no-heading", "-n", "--max-count=10", "-i"]
            grepArgs.append(contentsOf: [pattern, searchPath])
            grepArgs.append(contentsOf: ["--glob", "!.build", "--glob", "!node_modules", "--glob", "!.git"])

            let (output, _, exitCode) = await shellExec(args: grepArgs, cwd: workspace, timeout: 10_000)
            if exitCode == 0 {
                for line in output.components(separatedBy: "\n") where !line.isEmpty {
                    let parts = line.split(separator: ":", maxSplits: 2).map(String.init)
                    guard parts.count >= 3 else { continue }
                    let filePath = parts[0]
                    let lineNum = Int(parts[1]) ?? 0
                    let content = parts[2].trimmingCharacters(in: .whitespaces)
                    let contentLower = content.lowercased()
                    var score = 0.5
                    for token in queryTokens where contentLower.contains(token) { score += 0.8 }
                    if contentLower.contains("func ") || contentLower.contains("class ") ||
                       contentLower.contains("struct ") || contentLower.contains("protocol ") ||
                       contentLower.contains("enum ") || contentLower.contains("def ") ||
                       contentLower.contains("function ") {
                        score += 1.5
                    }
                    let relPath = filePath.hasPrefix(workspace) ? String(filePath.dropFirst(workspace.count + 1)) : filePath
                    grepResults.append(FallbackResult(file: relPath, line: lineNum, snippet: content, score: score))
                }
            }
        }

        var seen = Set<String>()
        let deduped = grepResults.sorted().filter { r in
            let key = "\(r.file):\(r.line)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        let top = Array(deduped.prefix(numResults))

        if top.isEmpty {
            return success([
                "title": "semantic_search",
                "query": query,
                "detail": "No results found",
                "output": "No matches found for: \(query)",
                "count": "0"
            ], startDate: startDate)
        }

        var output = ""
        for (i, r) in top.enumerated() {
            let lineInfo = r.line > 0 ? ":\(r.line)" : ""
            output += "\(i + 1). \(r.file)\(lineInfo) (score: \(String(format: "%.1f", r.score)))\n"
            if !r.snippet.isEmpty {
                let trimmed = r.snippet.count > 120 ? String(r.snippet.prefix(120)) + "…" : r.snippet
                output += "   \(trimmed)\n"
            }
        }

        return success([
            "title": "semantic_search",
            "query": query,
            "detail": "\(top.count) results (grep fallback)",
            "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
            "count": "\(top.count)"
        ], startDate: startDate)
    }

    // MARK: - read_lints: Read current linter/diagnostic state without running a build

    private func executeReadLints(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let workspace = context.workspaceContext.workspacePath.path
        let rawPath = call.args["path"] ?? ""
        let severity = call.args["severity"] ?? "all"  // all, error, warning
        let maxCount = Int(call.args["limit"] ?? "50") ?? 50

        // Strategy: Detect project type and use the fastest lint-only command
        var lintOutput = ""
        var lintErrors: [String] = []
        var toolUsed = ""

        // Check for Swift project
        let packageSwift = (workspace as NSString).appendingPathComponent("Package.swift")
        let xcodeproj = try? FileManager.default.contentsOfDirectory(atPath: workspace).first { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }

        if FileManager.default.fileExists(atPath: packageSwift) || xcodeproj != nil {
            // Swift: use `swift build --skip-link` for fast compile-only check, or swiftc -typecheck for single file
            toolUsed = "swift"
            if !rawPath.isEmpty {
                let filePath = (rawPath as NSString).isAbsolutePath ? rawPath : (workspace as NSString).appendingPathComponent(rawPath)
                let (out, err, _) = await shellExec(
                    args: ["/usr/bin/xcrun", "swiftc", "-typecheck", filePath],
                    cwd: workspace, timeout: 30_000
                )
                lintOutput = out
                if !err.isEmpty { lintErrors.append(err) }
            } else {
                let (out, err, _) = await shellExec(
                    args: ["/usr/bin/swift", "build", "--skip-link", "2>&1"],
                    cwd: workspace, timeout: 60_000
                )
                lintOutput = out + "\n" + err
            }
        }

        // Check for Node/TS project
        let packageJson = (workspace as NSString).appendingPathComponent("package.json")
        if FileManager.default.fileExists(atPath: packageJson) && toolUsed.isEmpty {
            // Try eslint first, then tsc --noEmit
            let eslintPath = (workspace as NSString).appendingPathComponent("node_modules/.bin/eslint")
            if FileManager.default.fileExists(atPath: eslintPath) {
                toolUsed = "eslint"
                var args = [eslintPath, "--format", "compact", "--no-color"]
                if !rawPath.isEmpty { args.append(rawPath) } else { args.append(".") }
                let (out, err, _) = await shellExec(args: args, cwd: workspace, timeout: 30_000)
                lintOutput = out
                if !err.isEmpty { lintErrors.append(err) }
            } else {
                // tsc --noEmit
                let tscPath = (workspace as NSString).appendingPathComponent("node_modules/.bin/tsc")
                if FileManager.default.fileExists(atPath: tscPath) {
                    toolUsed = "tsc"
                    let (out, err, _) = await shellExec(
                        args: [tscPath, "--noEmit", "--pretty", "false"],
                        cwd: workspace, timeout: 30_000
                    )
                    lintOutput = out
                    if !err.isEmpty { lintErrors.append(err) }
                }
            }
        }

        // Check for Cargo (Rust)
        let cargoToml = (workspace as NSString).appendingPathComponent("Cargo.toml")
        if FileManager.default.fileExists(atPath: cargoToml) && toolUsed.isEmpty {
            toolUsed = "cargo"
            let (out, err, _) = await shellExec(
                args: ["/usr/bin/env", "cargo", "check", "--message-format=short", "2>&1"],
                cwd: workspace, timeout: 60_000
            )
            lintOutput = out + "\n" + err
        }

        // Check for Go
        let goMod = (workspace as NSString).appendingPathComponent("go.mod")
        if FileManager.default.fileExists(atPath: goMod) && toolUsed.isEmpty {
            toolUsed = "go"
            let target = rawPath.isEmpty ? "./..." : rawPath
            let (out, err, _) = await shellExec(
                args: ["/usr/bin/env", "go", "vet", target],
                cwd: workspace, timeout: 30_000
            )
            lintOutput = out + "\n" + err
        }

        // Fallback: no recognized project type
        if toolUsed.isEmpty {
            return failure(
                "No recognized linter found. Supported: Swift (Package.swift/xcodeproj), Node (eslint/tsc), Cargo, Go.",
                errorCode: "validation", startDate: startDate
            )
        }

        // Parse and filter diagnostics
        let allLines = lintOutput.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let filtered: [String]
        switch severity {
        case "error":
            filtered = allLines.filter { line in
                let lower = line.lowercased()
                return lower.contains("error") || lower.contains("fatal")
            }
        case "warning":
            filtered = allLines.filter { line in
                let lower = line.lowercased()
                return lower.contains("warning") || lower.contains("warn")
            }
        default:
            filtered = allLines
        }

        let limited = Array(filtered.prefix(maxCount))
        let errorCount = limited.filter { $0.lowercased().contains("error") }.count
        let warningCount = limited.filter { $0.lowercased().contains("warning") }.count

        let summary = "\(errorCount) errors, \(warningCount) warnings (via \(toolUsed))"

        return success([
            "title": "read_lints",
            "linter": toolUsed,
            "error_count": "\(errorCount)",
            "warning_count": "\(warningCount)",
            "detail": summary,
            "output": truncate(limited.joined(separator: "\n"), maxBytes: context.policy.maxBashOutputBytes),
            "total_diagnostics": "\(filtered.count)"
        ], startDate: startDate)
    }

    // MARK: - debug_context: Gather full debug context (git, open files, lints, terminal state)

    private func executeDebugContext(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let workspace = context.workspaceContext.workspacePath.path
        var sections: [String] = []

        // 1. Git status
        let (gitStatus, _, gitExit) = await shellExec(
            args: ["/usr/bin/git", "status", "--short", "--branch"],
            cwd: workspace, timeout: 5_000
        )
        if gitExit == 0 {
            sections.append("## Git Status\n\(gitStatus)")
        }

        // 2. Git diff (staged + unstaged, compact)
        let (gitDiff, _, _) = await shellExec(
            args: ["/usr/bin/git", "diff", "--stat", "HEAD"],
            cwd: workspace, timeout: 5_000
        )
        if !gitDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("## Git Diff (stat)\n\(gitDiff)")
        }

        // 3. Recent git log (last 5 commits)
        let (gitLog, _, _) = await shellExec(
            args: ["/usr/bin/git", "log", "--oneline", "-5"],
            cwd: workspace, timeout: 5_000
        )
        if !gitLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("## Recent Commits\n\(gitLog)")
        }

        // 4. Open files from workspace context
        let openFiles = context.workspaceContext.openFiles
        if !openFiles.isEmpty {
            var fileSection = "## Open Files (\(openFiles.count))\n"
            for file in openFiles {
                let lineCount = file.content.components(separatedBy: "\n").count
                fileSection += "- \(file.path) (\(lineCount) lines)\n"
            }
            sections.append(fileSection)
        }

        // 5. Active file and selection
        if let activeFile = context.workspaceContext.activeFilePath {
            sections.append("## Active File\n\(activeFile)")
        }
        if let selection = context.workspaceContext.activeSelection, !selection.isEmpty {
            let preview = selection.count > 200 ? String(selection.prefix(200)) + "..." : selection
            sections.append("## Active Selection\n```\n\(preview)\n```")
        }

        // 6. Quick lint check (errors only, fast)
        let lintCall = ToolCall(
            id: UUID().uuidString, name: "read_lints",
            args: ["severity": "error", "limit": "10"],
            sourceProvider: call.sourceProvider, swarmId: nil, scope: call.scope
        )
        let lintResult = await executeReadLints(call: lintCall, context: context, startDate: startDate)
        if lintResult.ok {
            let errorCount = lintResult.payload["error_count"] ?? "0"
            let warningCount = lintResult.payload["warning_count"] ?? "0"
            let linter = lintResult.payload["linter"] ?? "unknown"
            var lintSection = "## Linter Diagnostics (\(linter))\nErrors: \(errorCount), Warnings: \(warningCount)"
            if let output = lintResult.payload["output"], !output.isEmpty, errorCount != "0" {
                lintSection += "\n```\n\(output.prefix(1000))\n```"
            }
            sections.append(lintSection)
        }

        // 7. Debug log summary (if any active session)
        let queryCall = ToolCall(
            id: UUID().uuidString, name: "debug_query",
            args: ["format": "summary", "limit": "5"],
            sourceProvider: call.sourceProvider, swarmId: nil, scope: call.scope
        )
        let queryResult = await executeDebugQuery(call: queryCall, context: context, startDate: startDate)
        if queryResult.ok, let output = queryResult.payload["output"], !output.isEmpty,
           output != "0 log entries" {
            sections.append("## Debug Log Summary\n\(output)")
        }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        let fullContext = sections.joined(separator: "\n\n")

        return ToolResult(ok: true, payload: [
            "title": "debug_context",
            "detail": "Debug context gathered: \(sections.count) sections",
            "output": truncate(fullContext, maxBytes: context.policy.maxBashOutputBytes),
            "sections": "\(sections.count)"
        ], durationMs: ms)
    }
}
