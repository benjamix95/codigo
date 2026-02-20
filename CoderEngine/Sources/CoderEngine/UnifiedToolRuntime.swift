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

    public init(
        sandboxMode: String = "workspace-write", askForApproval: String = "never",
        timeoutMs: Int = 60_000
    ) {
        self.sandboxMode = sandboxMode
        self.askForApproval = askForApproval
        self.timeoutMs = timeoutMs
    }
}

public struct ToolExecutionContext: Sendable {
    public let workspaceContext: WorkspaceContext
    public let policy: ToolRuntimePolicy
    public let executionScope: ExecutionScope

    public init(
        workspaceContext: WorkspaceContext, policy: ToolRuntimePolicy = ToolRuntimePolicy(),
        executionScope: ExecutionScope = .agent
    ) {
        self.workspaceContext = workspaceContext
        self.policy = policy
        self.executionScope = executionScope
    }
}

public actor UnifiedToolRuntime {
    /// All tool names supported by this runtime. Kept in sync with `run(_:context:startDate:)`.
    public static let supportedToolNames: [String] = [
        "read", "glob", "grep", "edit", "write", "patch", "bash",
        "ls", "mkdir", "web_search", "mcp",
    ]

    public init() {}

    public func execute(_ call: ToolCall, context: ToolExecutionContext) async -> [StreamEvent] {
        let start = Date()
        var basePayload: [String: String] = [
            "tool_call_id": call.id,
            "tool": call.name,
            "status": "started",
        ]
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
            case "read", "glob", "grep", "ls":
                return result.ok ? "read_batch_completed" : "tool_execution_error"
            case "edit", "write", "patch": return result.ok ? "file_change" : "tool_execution_error"
            case "bash": return result.ok ? "command_execution" : "tool_execution_error"
            case "mkdir": return result.ok ? "file_change" : "tool_execution_error"
            case "web_search": return result.ok ? "web_search_completed" : "web_search_failed"
            case "mcp": return result.ok ? "mcp_tool_call" : "tool_execution_error"
            default: return result.ok ? "mcp_tool_call" : "tool_execution_error"
            }
        }()
        events.append(.raw(type: eventType, payload: completedPayload))
        return events
    }

    // MARK: - Tool Dispatch

    private func run(_ call: ToolCall, context: ToolExecutionContext, startDate: Date) async
        -> ToolResult
    {
        do {
            switch call.name {

            // ── read: Read file content ───────────────────────────────────
            case "read":
                let path = resolvePath(
                    call.args["path"], workspace: context.workspaceContext.workspacePath.path)
                guard let path else {
                    return failure("Missing required argument: path", startDate: startDate)
                }
                guard FileManager.default.fileExists(atPath: path) else {
                    return failure(
                        "File not found: \(path)", startDate: startDate, payload: ["path": path])
                }
                let content = try String(contentsOfFile: path, encoding: .utf8)
                let lineCount = content.components(separatedBy: "\n").count
                return success(
                    [
                        "title": "Read • \((path as NSString).lastPathComponent)",
                        "path": path,
                        "file": path,
                        "files": path,
                        "count": "1",
                        "output": String(content.prefix(12_000)),
                        "detail": "\(lineCount) lines",
                    ], startDate: startDate)

            // ── ls: List directory contents ───────────────────────────────
            case "ls":
                let pathArg = call.args["path"] ?? call.args["directory"] ?? "."
                let resolved =
                    resolvePath(pathArg, workspace: context.workspaceContext.workspacePath.path)
                    ?? pathArg
                guard FileManager.default.fileExists(atPath: resolved) else {
                    return failure(
                        "Directory not found: \(resolved)", startDate: startDate,
                        payload: ["path": resolved])
                }
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir)
                guard isDir.boolValue else {
                    return failure(
                        "Not a directory: \(resolved)", startDate: startDate,
                        payload: ["path": resolved])
                }
                let entries = try FileManager.default.contentsOfDirectory(atPath: resolved).sorted()
                var lines: [String] = []
                for entry in entries.prefix(500) {
                    let fullPath = (resolved as NSString).appendingPathComponent(entry)
                    var entryIsDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: fullPath, isDirectory: &entryIsDir)
                    lines.append(entryIsDir.boolValue ? "\(entry)/" : entry)
                }
                let output = lines.joined(separator: "\n")
                return success(
                    [
                        "title": "List • \(pathArg)",
                        "path": resolved,
                        "detail": "\(entries.count) entries",
                        "output": output,
                    ], startDate: startDate)

            // ── glob: Find files by pattern ──────────────────────────────
            case "glob":
                let pattern = call.args["pattern"] ?? "*"
                let escapedPattern = pattern.replacingOccurrences(of: "'", with: "'\\''")
                let cmd =
                    "find . -maxdepth 8 -name '\(escapedPattern)' -not -path '*/.*' -not -path '*/node_modules/*' -not -path '*/.build/*' | head -n 300 | sort"
                return await runBash(
                    command: cmd, cwd: context.workspaceContext.workspacePath, startDate: startDate,
                    title: "Glob • \(pattern)", timeoutMs: context.policy.timeoutMs)

            // ── grep: Search text in files ────────────────────────────────
            case "grep":
                let query = call.args["query"] ?? ""
                guard !query.isEmpty else {
                    return failure("Missing required argument: query", startDate: startDate)
                }
                let scope = call.args["pathScope"] ?? call.args["path"] ?? "."
                let escapedQuery = query.replacingOccurrences(of: "'", with: "'\\''")
                let escapedScope = scope.replacingOccurrences(of: "'", with: "'\\''")
                // Try rg first, fall back to grep
                let cmd =
                    "if command -v rg &>/dev/null; then rg -n --no-heading '\(escapedQuery)' '\(escapedScope)' | head -n 200; else grep -rn '\(escapedQuery)' '\(escapedScope)' | head -n 200; fi"
                return await runBash(
                    command: cmd, cwd: context.workspaceContext.workspacePath, startDate: startDate,
                    title: "Grep • \(query)", timeoutMs: context.policy.timeoutMs)

            // ── edit / write: Write full file content ─────────────────────
            case "edit", "write":
                guard let pathArg = call.args["path"] else {
                    return failure("Missing required argument: path", startDate: startDate)
                }
                let path =
                    resolvePath(pathArg, workspace: context.workspaceContext.workspacePath.path)
                    ?? pathArg
                let content = call.args["content"] ?? ""
                // Ensure parent directory exists
                let parentDir = (path as NSString).deletingLastPathComponent
                if !FileManager.default.fileExists(atPath: parentDir) {
                    try FileManager.default.createDirectory(
                        atPath: parentDir, withIntermediateDirectories: true)
                }
                let oldContent = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                let newLines = content.components(separatedBy: "\n").count
                let oldLines = oldContent.components(separatedBy: "\n").count
                let added = max(0, newLines - oldLines)
                let removed = max(0, oldLines - newLines)
                let diffPreview = buildDiffPreview(old: oldContent, new: content)
                return success(
                    [
                        "title": "Edit • \((path as NSString).lastPathComponent)",
                        "path": path,
                        "file": path,
                        "linesAdded": "\(added)",
                        "linesRemoved": "\(removed)",
                        "diffPreview": String(diffPreview.prefix(4_000)),
                        "detail": "\(newLines) lines written",
                    ], startDate: startDate)

            // ── patch: Surgical search-and-replace within a file ──────────
            case "patch":
                guard let pathArg = call.args["path"] else {
                    return failure("Missing required argument: path", startDate: startDate)
                }
                let path =
                    resolvePath(pathArg, workspace: context.workspaceContext.workspacePath.path)
                    ?? pathArg
                guard FileManager.default.fileExists(atPath: path) else {
                    return failure(
                        "File not found: \(path)", startDate: startDate, payload: ["path": path])
                }
                let oldContent = try String(contentsOfFile: path, encoding: .utf8)

                // Support two modes:
                // 1. search + replace: find exact text and replace it
                // 2. old_str + new_str: alias for search/replace (Cursor-style)
                let search = call.args["search"] ?? call.args["old_str"] ?? ""
                let replace = call.args["replace"] ?? call.args["new_str"] ?? ""

                guard !search.isEmpty else {
                    return failure(
                        "Missing required argument: search (the text to find and replace)",
                        startDate: startDate, payload: ["path": path])
                }

                guard oldContent.contains(search) else {
                    // Provide helpful context when search string not found
                    let lines = oldContent.components(separatedBy: "\n")
                    let searchLines = search.components(separatedBy: "\n")
                    let firstSearchLine =
                        searchLines.first?.trimmingCharacters(in: .whitespaces) ?? ""
                    var hint = "Search string not found in file."
                    if !firstSearchLine.isEmpty {
                        let nearMatches = lines.enumerated().filter {
                            $0.element.trimmingCharacters(in: .whitespaces).contains(
                                firstSearchLine)
                        }.prefix(3)
                        if !nearMatches.isEmpty {
                            hint +=
                                " Partial matches near lines: "
                                + nearMatches.map { "L\($0.offset + 1)" }.joined(separator: ", ")
                        }
                    }
                    return failure(
                        hint, startDate: startDate,
                        payload: [
                            "path": path,
                            "detail": "search text not found",
                        ])
                }

                let occurrences = oldContent.components(separatedBy: search).count - 1
                let newContent = oldContent.replacingOccurrences(of: search, with: replace)
                try newContent.write(toFile: path, atomically: true, encoding: .utf8)
                let diffPreview = buildDiffPreview(old: oldContent, new: newContent)
                let newLines = newContent.components(separatedBy: "\n").count
                let oldLines = oldContent.components(separatedBy: "\n").count
                return success(
                    [
                        "title": "Patch • \((path as NSString).lastPathComponent)",
                        "path": path,
                        "file": path,
                        "linesAdded": "\(max(0, newLines - oldLines))",
                        "linesRemoved": "\(max(0, oldLines - newLines))",
                        "diffPreview": String(diffPreview.prefix(4_000)),
                        "detail": "\(occurrences) occurrence(s) replaced",
                    ], startDate: startDate)

            // ── mkdir: Create directory ───────────────────────────────────
            case "mkdir":
                guard let pathArg = call.args["path"] else {
                    return failure("Missing required argument: path", startDate: startDate)
                }
                let path =
                    resolvePath(pathArg, workspace: context.workspaceContext.workspacePath.path)
                    ?? pathArg
                try FileManager.default.createDirectory(
                    atPath: path, withIntermediateDirectories: true)
                return success(
                    [
                        "title": "mkdir • \((path as NSString).lastPathComponent)",
                        "path": path,
                        "detail": "Directory created",
                    ], startDate: startDate)

            // ── bash: Run shell command ───────────────────────────────────
            case "bash":
                let command = call.args["command"] ?? ""
                guard !command.isEmpty else {
                    return failure("Missing required argument: command", startDate: startDate)
                }
                return await runBash(
                    command: command, cwd: context.workspaceContext.workspacePath,
                    startDate: startDate, title: "Bash", timeoutMs: context.policy.timeoutMs)

            // ── web_search: Search the web ────────────────────────────────
            case "web_search":
                let query = call.args["query"] ?? ""
                guard !query.isEmpty else {
                    return failure("Missing required argument: query", startDate: startDate)
                }
                // Use curl to search via DuckDuckGo lite (works without API key)
                let escapedQuery = query.replacingOccurrences(of: "'", with: "'\\''")
                    .replacingOccurrences(of: " ", with: "+")
                let cmd =
                    "curl -sL 'https://lite.duckduckgo.com/lite/?q=\(escapedQuery)' | sed 's/<[^>]*>//g' | sed '/^$/d' | head -n 80"
                return await runBash(
                    command: cmd, cwd: context.workspaceContext.workspacePath, startDate: startDate,
                    title: "Web Search • \(query)", timeoutMs: min(context.policy.timeoutMs, 15_000)
                )

            // ── mcp: Invoke MCP tool ──────────────────────────────────────
            case "mcp":
                let tool = call.args["tool"] ?? "mcp"
                let argsJson = call.args["args"] ?? "{}"
                return success(
                    [
                        "title": "MCP • \(tool)",
                        "tool": tool,
                        "detail":
                            "MCP tool call: \(tool) with args: \(String(argsJson.prefix(500)))",
                    ], startDate: startDate)

            default:
                return failure(
                    "Unknown tool: \(call.name). Supported tools: \(Self.supportedToolNames.joined(separator: ", "))",
                    startDate: startDate)
            }
        } catch {
            return failure(error.localizedDescription, startDate: startDate)
        }
    }

    // MARK: - Bash Execution

    private func runBash(
        command: String, cwd: URL, startDate: Date, title: String, timeoutMs: Int = 60_000
    ) async -> ToolResult {
        do {
            let result = try await withThrowingTaskGroup(
                of: (output: [String], terminationStatus: Int32).self
            ) { group in
                group.addTask {
                    try await ProcessRunner.runCollecting(
                        executable: "/bin/zsh",
                        arguments: ["-lc", command],
                        workingDirectory: cwd
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                    throw ToolTimeoutError()
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
            let output = result.output.joined(separator: "\n")
            if result.terminationStatus == 0 {
                return success(
                    [
                        "title": title,
                        "command": command,
                        "cwd": cwd.path,
                        "output": String(output.prefix(8_000)),
                        "detail": "exit 0",
                    ], startDate: startDate)
            }
            return failure(
                "exit \(result.terminationStatus)", startDate: startDate,
                payload: [
                    "title": title,
                    "command": command,
                    "cwd": cwd.path,
                    "output": String(output.prefix(8_000)),
                    "exit_code": "\(result.terminationStatus)",
                ])
        } catch is ToolTimeoutError {
            return failure(
                "Command timed out after \(timeoutMs / 1000)s", startDate: startDate,
                payload: [
                    "title": title,
                    "command": command,
                    "cwd": cwd.path,
                ])
        } catch {
            return failure(
                error.localizedDescription, startDate: startDate,
                payload: [
                    "title": title,
                    "command": command,
                    "cwd": cwd.path,
                ])
        }
    }

    // MARK: - Helpers

    private func resolvePath(_ rawPath: String?, workspace: String) -> String? {
        guard let rawPath = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rawPath.isEmpty
        else { return nil }
        if (rawPath as NSString).isAbsolutePath { return rawPath }
        return (workspace as NSString).appendingPathComponent(rawPath)
    }

    private func success(_ payload: [String: String], startDate: Date) -> ToolResult {
        ToolResult(
            ok: true, payload: payload,
            durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000)))
    }

    private func failure(_ message: String, startDate: Date, payload: [String: String] = [:])
        -> ToolResult
    {
        var p = payload
        p["title"] = p["title"] ?? "Tool error"
        p["detail"] = message
        p["stderr"] = message
        return ToolResult(
            ok: false, payload: p,
            durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000)))
    }

    private func buildDiffPreview(old: String, new: String) -> String {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        let maxCount = min(max(oldLines.count, newLines.count), 120)
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
            if out.count >= 60 { break }
        }
        return out.joined(separator: "\n")
    }
}

// MARK: - Internal Error Types

private struct ToolTimeoutError: Error {}
