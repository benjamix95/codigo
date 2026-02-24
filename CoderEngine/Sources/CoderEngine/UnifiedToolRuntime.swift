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
        case .timeout(let tool, let ms): return "Timeout su \(tool) (\(ms)ms)"
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

    public init(
        executionController: ExecutionController? = nil,
        executionScope: ExecutionScope = .agent,
        mcpSessions: MCPSessionManager = MCPSessionManager()
    ) {
        self.executionController = executionController
        self.executionScope = executionScope
        self.mcpSessions = mcpSessions
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
                let pattern = call.args["pattern"] ?? "*"
                let scopePath = call.args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "."
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
            case "grep":
                let query = call.args["query"] ?? ""
                let scope = call.args["pathScope"] ?? call.args["path"] ?? "."
                let fileType = call.args["fileType"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let contextLines = Int(call.args["context_lines"] ?? "") ?? 0
                var cmd = "rg -n --no-heading"
                if !fileType.isEmpty {
                    cmd += " --type '\(shellEscaped(fileType))'"
                }
                if contextLines > 0 {
                    cmd += " -C \(min(contextLines, 10))"
                }
                cmd += " '\(shellEscaped(query))' '\(shellEscaped(scope))' | head -n 500"
                return await runBash(
                    command: cmd,
                    cwd: context.workspaceContext.workspacePath,
                    startDate: startDate,
                    title: "Grep \(query)",
                    timeoutMs: context.policy.timeoutMs,
                    maxOutputBytes: context.policy.maxBashOutputBytes,
                    policy: context.policy
                )
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
                let query = call.args["query"] ?? ""
                return success([
                    "title": "Web search",
                    "query": query,
                    "detail": "Delegato al provider web"
                ], startDate: startDate)
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
                "MCP disabilitato dalla policy",
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
                "Manca il nome tool MCP",
                errorCode: ToolRuntimeError.validation("Manca il nome tool MCP").errorCode,
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
                payload["detail"] = "Il server MCP ha risposto con isError=true"
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
                "MCP disabilitato dalla policy",
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
                "detail": "\(tools.count) tool trovati"
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
                "MCP disabilitato dalla policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate
            )
        }
        let toolName = (call.args["tool"] ?? call.args["mcp_tool"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolName.isEmpty else {
            return failure(
                "Manca il nome tool",
                errorCode: ToolRuntimeError.validation("tool missing").errorCode,
                startDate: startDate
            )
        }

        do {
            let serverId = call.args["server"] ?? call.args["server_id"]
            let desc = try await mcpSessions.describeTool(serverId: serverId, toolName: toolName)
            guard let desc else {
                return failure(
                    "Tool MCP non trovato",
                    errorCode: ToolRuntimeError.mcpUnavailable("Tool MCP non trovato").errorCode,
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
                "MCP disabilitato dalla policy",
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
            "detail": "\(states.count) server"
        ], startDate: startDate)
    }

    private func executeMCPListServers(context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabilitato dalla policy",
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
            "detail": "\(servers.count) server"
        ], startDate: startDate)
    }

    private func executeMCPReconnect(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabilitato dalla policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate
            )
        }
        let serverId = (call.args["server"] ?? call.args["server_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serverId.isEmpty else {
            return failure("server obbligatorio", errorCode: "validation", startDate: startDate)
        }
        do {
            try await mcpSessions.reconnect(serverId: serverId)
            return success([
                "title": "MCP reconnect",
                "tool": "mcp_reconnect",
                "server_id": serverId,
                "detail": "Connessione ristabilita"
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
        let kind = (call.args["kind"] ?? "all").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let kindPattern: String
        switch kind {
        case "class": kindPattern = "class\\s+"
        case "struct": kindPattern = "struct\\s+"
        case "enum": kindPattern = "enum\\s+"
        case "protocol": kindPattern = "protocol\\s+"
        case "function", "func": kindPattern = "func\\s+"
        default: kindPattern = "(class|struct|enum|protocol|func)\\s+"
        }
        let cmd = "rg -n \"\(kindPattern)\(shellEscaped(query))\" --glob '*.swift' . | head -n 200"
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

    private func validate(call: ToolCall, normalizedName: String) throws {
        switch normalizedName {
        case "read", "write", "edit", "read_range", "list_dir", "read_json", "write_json", "tail_log",
             "str_replace", "create_file":
            let path = call.args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if path.isEmpty && normalizedName != "list_dir" {
                throw ToolRuntimeError.validation("path is required")
            }
        case "grep", "web_search", "search_symbols":
            let query = call.args["query"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if query.isEmpty {
                throw ToolRuntimeError.validation("query is required")
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
             "workspace_stats", "dependency_audit", "tail_log":
            return ok ? "read_batch_completed" : "tool_execution_error"
        case "edit", "write", "str_replace", "create_file":
            return ok ? "file_change" : "tool_execution_error"
        case "bash":
            return ok ? "command_execution" : "tool_execution_error"
        case "web_search":
            return ok ? "web_search_completed" : "web_search_failed"
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
}
