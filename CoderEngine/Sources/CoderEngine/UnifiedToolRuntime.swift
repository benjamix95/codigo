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

public struct ToolRuntimePolicy: Sendable {
    public let sandboxMode: String
    public let askForApproval: String
    public let timeoutMs: Int

    public init(sandboxMode: String = "workspace-write", askForApproval: String = "never", timeoutMs: Int = 30_000) {
        self.sandboxMode = sandboxMode
        self.askForApproval = askForApproval
        self.timeoutMs = timeoutMs
    }
}

public struct ToolExecutionContext: Sendable {
    public let workspaceContext: WorkspaceContext
    public let policy: ToolRuntimePolicy
    public let executionScope: ExecutionScope

    public init(workspaceContext: WorkspaceContext, policy: ToolRuntimePolicy = ToolRuntimePolicy(), executionScope: ExecutionScope = .agent) {
        self.workspaceContext = workspaceContext
        self.policy = policy
        self.executionScope = executionScope
    }
}

public actor UnifiedToolRuntime {
    private let executionController: ExecutionController?
    private let executionScope: ExecutionScope

    public init(executionController: ExecutionController? = nil, executionScope: ExecutionScope = .agent) {
        self.executionController = executionController
        self.executionScope = executionScope
    }

    public func execute(_ call: ToolCall, context: ToolExecutionContext) async -> [StreamEvent] {
        let start = Date()
        var basePayload: [String: String] = [
            "tool_call_id": call.id,
            "tool": call.name,
            "status": "started"
        ]
        if let command = call.args["command"], !command.isEmpty {
            basePayload["command"] = command
            basePayload["title"] = "Bash"
            basePayload["detail"] = command
        }
        if let cwd = call.args["cwd"], !cwd.isEmpty {
            basePayload["cwd"] = cwd
        }
        if let query = call.args["query"], !query.isEmpty {
            basePayload["query"] = query
        }
        if let swarmId = call.swarmId, !swarmId.isEmpty {
            basePayload["swarm_id"] = swarmId
            basePayload["group_id"] = "swarm-\(swarmId)"
        }

        var events: [StreamEvent] = [.raw(type: "mcp_tool_call", payload: basePayload)]
        let result = await run(call, context: context, startDate: start)
        var completedPayload = result.payload
        completedPayload["tool_call_id"] = call.id
        completedPayload["tool"] = call.name
        completedPayload["duration_ms"] = "\(result.durationMs)"
        completedPayload["status"] = result.ok ? "completed" : "failed"
        if let swarmId = call.swarmId, !swarmId.isEmpty {
            completedPayload["swarm_id"] = swarmId
            completedPayload["group_id"] = "swarm-\(swarmId)"
        }

        let eventType: String = {
            switch call.name {
            case "read", "glob", "grep": return result.ok ? "read_batch_completed" : "tool_execution_error"
            case "edit", "write": return result.ok ? "file_change" : "tool_execution_error"
            case "bash": return result.ok ? "command_execution" : "tool_execution_error"
            case "web_search": return result.ok ? "web_search_completed" : "web_search_failed"
            case "mcp": return result.ok ? "mcp_tool_call" : "tool_execution_error"
            default: return result.ok ? "mcp_tool_call" : "tool_execution_error"
            }
        }()
        events.append(.raw(type: eventType, payload: completedPayload))
        return events
    }

    private func run(_ call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        do {
            switch call.name {
            case "read":
                let path = resolvePath(
                    call.args["path"],
                    workspace: context.workspaceContext.workspacePath.path,
                    sandboxMode: context.policy.sandboxMode
                )
                guard let path else { return failure("Path mancante", startDate: startDate) }
                let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                return success(["title": "Read \(path)", "path": path, "output": String(content.prefix(6000))], startDate: startDate)
            case "glob":
                let pattern = call.args["pattern"] ?? "*"
                let cmd = "find . -name '\(pattern.replacingOccurrences(of: "'", with: "'\\''"))' | head -n 200"
                return await runBash(command: cmd, cwd: context.workspaceContext.workspacePath, startDate: startDate, title: "Glob \(pattern)")
            case "grep":
                let query = call.args["query"] ?? ""
                let scope = call.args["pathScope"] ?? "."
                let cmd = "rg -n '\(query.replacingOccurrences(of: "'", with: "'\\''"))' \(scope.replacingOccurrences(of: "'", with: "'\\''")) | head -n 200"
                return await runBash(command: cmd, cwd: context.workspaceContext.workspacePath, startDate: startDate, title: "Grep \(query)")
            case "edit", "write":
                guard let pathArg = call.args["path"] else { return failure("Path mancante", startDate: startDate) }
                guard let path = resolvePath(
                    pathArg,
                    workspace: context.workspaceContext.workspacePath.path,
                    sandboxMode: context.policy.sandboxMode
                ) else {
                    return failure("Path non consentito dal sandbox: \(pathArg)", startDate: startDate)
                }
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
            case "bash":
                let command = call.args["command"] ?? ""
                return await runBash(command: command, cwd: context.workspaceContext.workspacePath, startDate: startDate, title: "Bash")
            case "web_search":
                let query = call.args["query"] ?? ""
                return success(["title": "Web search", "query": query, "detail": "Delegato al provider web"], startDate: startDate)
            case "mcp":
                let tool = call.args["tool"] ?? "mcp"
                return success(["title": "MCP \(tool)", "tool": tool, "detail": "Tool call richiesto dal modello"], startDate: startDate)
            default:
                return failure("Tool non supportato: \(call.name)", startDate: startDate)
            }
        } catch {
            return failure(error.localizedDescription, startDate: startDate)
        }
    }

    private func runBash(command: String, cwd: URL, startDate: Date, title: String) async -> ToolResult {
        do {
            let result = try await ProcessRunner.runCollecting(
                executable: "/bin/zsh",
                arguments: ["-lc", command],
                workingDirectory: cwd,
                executionController: executionController,
                scope: executionScope
            )
            let output = result.output.joined(separator: "\n")
            if result.terminationStatus == 0 {
                return success([
                    "title": title,
                    "command": command,
                    "cwd": cwd.path,
                    "output": String(output.prefix(6000))
                ], startDate: startDate)
            }
            return failure("exit \(result.terminationStatus): \(String(output.prefix(3000)))", startDate: startDate, payload: [
                "title": title,
                "command": command,
                "cwd": cwd.path,
                "output": String(output.prefix(6000))
            ])
        } catch {
            return failure(error.localizedDescription, startDate: startDate, payload: [
                "title": title,
                "command": command,
                "cwd": cwd.path
            ])
        }
    }

    private func resolvePath(_ rawPath: String?, workspace: String, sandboxMode: String) -> String? {
        guard let rawPath = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty else { return nil }
        let workspaceURL = URL(fileURLWithPath: workspace).standardizedFileURL
        let resolvedURL: URL
        if (rawPath as NSString).isAbsolutePath {
            resolvedURL = URL(fileURLWithPath: rawPath).standardizedFileURL
        } else {
            resolvedURL = workspaceURL.appendingPathComponent(rawPath).standardizedFileURL
        }

        // Enforce workspace confinement except in full-access sandbox.
        if sandboxMode != "danger-full-access" {
            let workspacePath = workspaceURL.path.hasSuffix("/") ? workspaceURL.path : workspaceURL.path + "/"
            let resolvedPath = resolvedURL.path
            if resolvedPath != workspaceURL.path && !resolvedPath.hasPrefix(workspacePath) {
                return nil
            }
        }
        return resolvedURL.path
    }

    private func success(_ payload: [String: String], startDate: Date) -> ToolResult {
        ToolResult(ok: true, payload: payload, durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000)))
    }

    private func failure(_ message: String, startDate: Date, payload: [String: String] = [:]) -> ToolResult {
        var p = payload
        p["title"] = p["title"] ?? "Tool error"
        p["detail"] = message
        p["stderr"] = message
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
}
