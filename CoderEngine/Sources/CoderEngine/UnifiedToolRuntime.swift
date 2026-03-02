import Foundation
import os

public struct ToolCall: Sendable {
    public let id: String
    public let name: String
    public let args: [String: String]
    public let sourceProvider: String
    public let swarmId: String?
    public let scope: ExecutionScope
    /// Rich arguments preserving native types (arrays, objects, numbers, booleans).
    /// When present, MCP tool calls prefer these over the string-only `args`.
    public let richArgs: [String: any Sendable]?

    public init(
        id: String,
        name: String,
        args: [String: String],
        sourceProvider: String,
        swarmId: String?,
        scope: ExecutionScope,
        richArgs: [String: any Sendable]? = nil
    ) {
        self.id = id
        self.name = name
        self.args = args
        self.sourceProvider = sourceProvider
        self.swarmId = swarmId
        self.scope = scope
        self.richArgs = richArgs
    }
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
    public let enforceMCPEditOnly: Bool
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
        enforceMCPEditOnly: Bool = true,
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
        self.enforceMCPEditOnly = enforceMCPEditOnly
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

public struct ToolRuntimeDebugSnapshot: Sendable, Equatable {
    public let hasCodebaseIndex: Bool
    public let workspacePaths: [String]
    public let excludedPaths: [String]
    public let executionScope: ExecutionScope

    public init(
        hasCodebaseIndex: Bool,
        workspacePaths: [String],
        excludedPaths: [String],
        executionScope: ExecutionScope
    ) {
        self.hasCodebaseIndex = hasCodebaseIndex
        self.workspacePaths = workspacePaths
        self.excludedPaths = excludedPaths
        self.executionScope = executionScope
    }
}

@MainActor
public protocol TerminalBridge: AnyObject {
    func executeInTerminal(command: String, cwd: String?, label: String) async -> (output: String, exitCode: Int32)
    func readTerminalOutput(sessionId: String?, lastN: Int) -> String
    func allSessionsSummary(lastN: Int) -> String
}

@MainActor
public protocol BrowserBridge: AnyObject {
    func navigate(to url: String) async
    func goBack() async
    func goForward() async
    func reload() async
    func takeScreenshot() async -> Data?
    func getConsoleLogs(level: String?) -> String
    func clearConsoleLogs()
    func evaluateJS(_ script: String) async -> String?
    func click(selector: String) async -> Bool
    func type(selector: String, text: String) async -> Bool
    func getPageContent() async -> String?
    func getPageTitle() async -> String?
    func getCurrentURL() -> String?
}

public actor UnifiedToolRuntime {
    private static let logger = Logger(subsystem: "com.codigo.CoderEngine", category: "UnifiedToolRuntime")

    private let executionController: ExecutionController?
    private let executionScope: ExecutionScope
    public let mcpSessions: MCPSessionManager

    /// Codebase index tools (created lazily when needed)
    private var indexTools: CodebaseIndexTools?
    /// Direct reference to CodebaseIndex for SemanticIndex access
    private var codebaseIndex: CodebaseIndex?
    private let workspacePaths: [URL]
    private let excludedPaths: [String]

    /// Web search service (Brave Search + DuckDuckGo fallback)
    private let webSearch: WebSearchService
    /// Web fetch service (HTML → Markdown)
    private let webFetch: WebFetchService

    /// Debug log server for structured debug logging
    public let debugLogServer = DebugLogServer()

    /// Tracks hypothesis lifecycle for debug_hypothesize ID validation.
    private var debugHypotheses: [String: DebugHypothesis] = [:]

    struct DebugHypothesis {
        var title: String
        var description: String
        var status: String
        var confidence: Int
        var rootCauseType: String
        var relatedFiles: [String]
        var relatedTests: [String]
        var evidence: [String]
        var createdAt: Date
    }

    /// Terminal bridge for IDE terminal integration
    private weak var terminalBridge: (any TerminalBridge)?
    /// Browser bridge for integrated browser control
    private weak var browserBridge: (any BrowserBridge)?

    public init(
        executionController: ExecutionController? = nil,
        executionScope: ExecutionScope = .agent,
        mcpSessions: MCPSessionManager = MCPSessionManager(),
        index: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        excludedPaths: [String] = [],
        webSearchProvider: String? = nil,
        webSearchApiKeys: [String: String]? = nil,
        terminalBridge: (any TerminalBridge)? = nil,
        browserBridge: (any BrowserBridge)? = nil
    ) {
        self.executionController = executionController
        self.executionScope = executionScope
        self.mcpSessions = mcpSessions
        self.codebaseIndex = index
        self.indexTools = index.map { CodebaseIndexTools(index: $0) }
        self.workspacePaths = workspacePaths
        self.excludedPaths = excludedPaths
        self.terminalBridge = terminalBridge
        self.browserBridge = browserBridge

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

    public func setBrowserBridge(_ bridge: (any BrowserBridge)?) {
        self.browserBridge = bridge
    }

    public func setTerminalBridge(_ bridge: (any TerminalBridge)?) {
        self.terminalBridge = bridge
    }

    public func debugSnapshot() -> ToolRuntimeDebugSnapshot {
        ToolRuntimeDebugSnapshot(
            hasCodebaseIndex: codebaseIndex != nil,
            workspacePaths: workspacePaths.map(\.path),
            excludedPaths: excludedPaths,
            executionScope: executionScope
        )
    }

    private func ensureIndexTools(for context: ToolExecutionContext) async -> CodebaseIndexTools {
        if let indexTools {
            return indexTools
        }

        let index = codebaseIndex ?? CodebaseIndex()
        codebaseIndex = index
        let tools = CodebaseIndexTools(index: index)
        indexTools = tools

        let requestedPaths = preferredWorkspacePaths(for: context)
        if !requestedPaths.isEmpty {
            let _ = await index.indexWorkspace(paths: requestedPaths, excludedPaths: excludedPaths)
        }

        return tools
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

    private func runShellCommand(_ command: String, timeout: Int = 15_000) async -> String {
        let (stdout, _, _) = await shellExec(
            args: ["/bin/zsh", "-lc", command],
            cwd: ".",
            timeout: timeout
        )
        return stdout
    }

    /// Tools that modify files and should trigger a codebase reindex.
    private static let fileChangingTools: Set<String> = [
        "edit", "write", "str_replace", "create_file", "delete_file",
        "parallel_apply", "regex_replace", "rename_symbol",
        "find_and_replace_all", "undo_edit", "write_json",
        "apply_diff", "debug_mark", "debug_clean",
    ]

    public func execute(_ call: ToolCall, context: ToolExecutionContext) async -> [StreamEvent] {
        let normalizedName = normalizeToolName(call.name)
        let start = Date()
        let basePayload = buildBasePayload(call: call, normalizedName: normalizedName)
        let startEventType = startEventTypeForTool(name: normalizedName, payload: basePayload)

        var events: [StreamEvent] = [.raw(type: startEventType, payload: basePayload)]
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

        let eventType = eventTypeForTool(name: normalizedName, ok: result.ok, payload: completedPayload)
        events.append(.raw(type: eventType, payload: completedPayload))

        // Auto-reindex modified files so semantic search stays fresh
        if result.ok, Self.fileChangingTools.contains(normalizedName) {
            await reindexModifiedFile(call: call, context: context)
        }

        return events
    }

    /// Re-indexes a single file after it has been modified by a tool.
    private func reindexModifiedFile(call: ToolCall, context: ToolExecutionContext) async {
        guard let index = codebaseIndex else { return }
        let path = call.args["path"] ?? call.args["file_path"] ?? call.args["file"] ?? call.args["target_path"] ?? ""
        guard !path.isEmpty else { return }

        let workspacePath = context.workspaceContext.workspacePath.path
        let absolutePath: String
        if (path as NSString).isAbsolutePath {
            absolutePath = path
        } else {
            absolutePath = (workspacePath as NSString).appendingPathComponent(path)
        }

        let relativePath: String
        if absolutePath.hasPrefix(workspacePath) {
            relativePath = String(absolutePath.dropFirst(workspacePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            relativePath = path
        }

        await index.indexSingleFile(absolutePath: absolutePath, relativePath: relativePath)
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
            case "read_terminal":
                return await executeReadTerminal(call: call, startDate: startDate)
            case "web_search":
                return await executeWebSearch(call: call, context: context, startDate: startDate)
            case "web_fetch":
                return await executeWebFetch(call: call, context: context, startDate: startDate)
            case "browser_navigate":
                return await executeBrowserNavigate(call: call, startDate: startDate)
            case "browser_screenshot":
                return await executeBrowserScreenshot(call: call, startDate: startDate)
            case "browser_console_logs":
                return await executeBrowserConsoleLogs(call: call, startDate: startDate)
            case "browser_click":
                return await executeBrowserClick(call: call, startDate: startDate)
            case "browser_type":
                return await executeBrowserType(call: call, startDate: startDate)
            case "browser_evaluate_js":
                return await executeBrowserEvaluateJS(call: call, startDate: startDate)
            case "browser_get_content":
                return await executeBrowserGetContent(call: call, startDate: startDate)
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
            case "debug_trace_analyze":
                return await executeDebugTraceAnalyze(call: call, context: context, startDate: startDate)
            case "debug_instrument":
                return await executeDebugInstrument(call: call, context: context, startDate: startDate)
            case "debug_timeline":
                return await executeDebugTimeline(call: call, context: context, startDate: startDate)
            case "debug_snapshot":
                return await executeDebugSnapshot(call: call, context: context, startDate: startDate)
            case "debug_test_check":
                return await executeDebugTestCheck(call: call, context: context, startDate: startDate)

            // Power tools
            case "apply_diff":
                return try executeApplyDiff(call: call, context: context, startDate: startDate)
            case "batch_read":
                return try executeBatchRead(call: call, context: context, startDate: startDate)
            case "diff_files":
                return await executeDiffFiles(call: call, context: context, startDate: startDate)
            case "git_status":
                return await executeGitStatus(call: call, context: context, startDate: startDate)
            case "git_show":
                return await executeGitShow(call: call, context: context, startDate: startDate)
            case "code_context":
                return await executeCodeContext(call: call, context: context, startDate: startDate)

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
            case "mcp_batch":
                return await executeMCPBatch(call: call, context: context, startDate: startDate)
            case "mcp_list_resources":
                return await executeMCPListResources(call: call, context: context, startDate: startDate)
            case "mcp_read_resource":
                return await executeMCPReadResource(call: call, context: context, startDate: startDate)
            case "mcp_subscribe":
                return await executeMCPSubscribe(call: call, context: context, startDate: startDate)
            case "mcp_list_prompts":
                return await executeMCPListPrompts(call: call, context: context, startDate: startDate)
            case "mcp_get_prompt":
                return await executeMCPGetPrompt(call: call, context: context, startDate: startDate)
            case "mcp_logs":
                return await executeMCPLogs(call: call, context: context, startDate: startDate)
            case "mcp_restart_server":
                return await executeMCPRestartServer(call: call, context: context, startDate: startDate)
            default:
                if context.policy.enableMCP {
                    if let route = MCPNativeToolRegistry.shared.routing[normalizedName] {
                        return await executeNativeMCPTool(
                            functionName: normalizedName,
                            route: route,
                            call: call,
                            context: context,
                            startDate: startDate
                        )
                    }
                    if canFallbackToMCP(toolName: normalizedName, call: call) {
                        return await executeMCPDirectToolFallback(
                            toolName: normalizedName,
                            call: call,
                            context: context,
                            startDate: startDate
                        )
                    }
                }
                throw ToolRuntimeError.validation("Unsupported tool: \(normalizedName)")
            }
        } catch let err as ToolRuntimeError {
            let isMCP = context.policy.enableMCP && (
                MCPNativeToolRegistry.shared.routing[normalizedName] != nil ||
                canFallbackToMCP(toolName: normalizedName, call: call)
            )
            let mcpPayload = isMCP ? ["is_mcp": "true"] : [String: String]()
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: mcpPayload)
        } catch {
            let isMCP = context.policy.enableMCP && (
                MCPNativeToolRegistry.shared.routing[normalizedName] != nil ||
                canFallbackToMCP(toolName: normalizedName, call: call)
            )
            let mcpPayload = isMCP ? ["is_mcp": "true"] : [String: String]()
            return failure(error.localizedDescription, errorCode: "unknown", startDate: startDate, payload: mcpPayload)
        }
    }

    private func canFallbackToMCP(toolName: String, call: ToolCall) -> Bool {
        if toolName == "mcp" || toolName == "mcp_call" || toolName.hasPrefix("mcp_") {
            return true
        }
        if isQualifiedMCPToolReference(toolName) {
            return true
        }
        if toolName.hasPrefix("coderide_") {
            return true
        }
        let hasToolArg = call.args["tool"] != nil || call.args["mcp_tool"] != nil
        let hasServerArg = call.args["server"] != nil || call.args["server_id"] != nil || call.args["mcp_server"] != nil
        return hasToolArg && (hasServerArg || toolName == "mcp" || toolName == "mcp_call")
    }

    private func resolveMCPServerArg(from args: [String: String]) -> String {
        (args["server"] ?? args["server_id"] ?? args["mcp_server"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isQualifiedMCPToolReference(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return false }
        return isValidMCPIdentifier(parts[0]) && isValidMCPIdentifier(parts[1])
    }

    private func isValidMCPIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = #"^[A-Za-z0-9_.:-]{1,128}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private struct MCPInvocation {
        let serverId: String?
        let toolName: String
        let arguments: [String: String]
    }

    private static let mcpWrapperKeys: Set<String> = [
        "name", "id", "tool", "mcp_tool", "server", "server_id", "mcp_server", "args"
    ]

    private func buildMCPInvocation(
        call: ToolCall,
        fallbackToolName: String? = nil
    ) throws -> MCPInvocation {
        let toolFromArgs = (call.args["tool"] ?? call.args["mcp_tool"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTool = (fallbackToolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedToolRaw = !toolFromArgs.isEmpty ? toolFromArgs : fallbackTool
        guard !requestedToolRaw.isEmpty else {
            throw ToolRuntimeError.validation("Missing MCP tool name")
        }

        let server = (call.args["server"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let serverID = (call.args["server_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let mcpServer = (call.args["mcp_server"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let serverCandidates = [server, serverID, mcpServer].filter { !$0.isEmpty }
        if Set(serverCandidates).count > 1 {
            throw ToolRuntimeError.validation("Conflicting MCP server values in server/server_id/mcp_server")
        }
        let explicitServer = serverCandidates.first

        let parsedServer: String?
        let parsedTool: String
        if requestedToolRaw.contains("/") {
            let parts = requestedToolRaw.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else {
                throw ToolRuntimeError.validation("Ambiguous MCP tool reference '\(requestedToolRaw)'")
            }
            guard isValidMCPIdentifier(parts[0]), isValidMCPIdentifier(parts[1]) else {
                throw ToolRuntimeError.validation("Invalid MCP server/tool identifier in '\(requestedToolRaw)'")
            }
            if let explicitServer, explicitServer != parts[0] {
                throw ToolRuntimeError.validation("Conflicting MCP server between tool reference and server argument")
            }
            parsedServer = parts[0]
            parsedTool = parts[1]
        } else {
            guard isValidMCPIdentifier(requestedToolRaw) else {
                throw ToolRuntimeError.validation("Invalid MCP tool identifier '\(requestedToolRaw)'")
            }
            if let explicitServer, !explicitServer.isEmpty, !isValidMCPIdentifier(explicitServer) {
                throw ToolRuntimeError.validation("Invalid MCP server identifier '\(explicitServer)'")
            }
            parsedServer = explicitServer
            parsedTool = requestedToolRaw
        }

        var mergedArgs: [String: String] = [:]
        let embeddedArgs = parseEmbeddedArgs(call.args["args"])
        for (key, value) in embeddedArgs {
            mergedArgs[key] = value
        }
        for (key, value) in call.args where !Self.mcpWrapperKeys.contains(key) {
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidMCPIdentifier(trimmedKey) else {
                throw ToolRuntimeError.validation("Unsupported MCP argument key '\(key)'")
            }
            mergedArgs[trimmedKey] = value
        }

        return MCPInvocation(serverId: parsedServer, toolName: parsedTool, arguments: mergedArgs)
    }

    public func executeMCP(call: ToolCall, context: ToolExecutionContext) async -> ToolResult {
        await executeMCPCall(call: call, context: context, startDate: Date())
    }

    private func executeMCPCall(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }
        let invocation: MCPInvocation
        do {
            invocation = try buildMCPInvocation(call: call)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }

        do {
            let result: (serverId: String, serverName: String, content: String, isError: Bool)
            if let rich = call.richArgs, !rich.isEmpty {
                var richFiltered = rich
                for key in Self.mcpWrapperKeys { richFiltered.removeValue(forKey: key) }
                result = try await mcpSessions.callToolRich(
                    serverId: invocation.serverId,
                    toolName: invocation.toolName,
                    arguments: richFiltered,
                    timeoutMs: context.policy.mcpPerCallTimeoutMs,
                    idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
                )
            } else {
                result = try await mcpSessions.callTool(
                    serverId: invocation.serverId,
                    toolName: invocation.toolName,
                    arguments: invocation.arguments,
                    timeoutMs: context.policy.mcpPerCallTimeoutMs,
                    idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
                )
            }

            var payload: [String: String] = [
                "title": "MCP \(result.serverName)/\(invocation.toolName)",
                "tool": "mcp",
                "mcp_server": result.serverName,
                "server_id": result.serverId,
                "mcp_tool": invocation.toolName,
                "output": truncate(result.content, maxBytes: context.policy.maxBashOutputBytes),
                "mcp_latency_ms": "\(max(1, Int(Date().timeIntervalSince(startDate) * 1000)))",
                "is_mcp": "true"
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
                "mcp_tool": invocation.toolName,
                "server_id": invocation.serverId ?? "",
                "is_mcp": "true"
            ])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: [
                "mcp_tool": invocation.toolName,
                "server_id": invocation.serverId ?? "",
                "is_mcp": "true"
            ])
        }
    }

    private func executeMCPListTools(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }

        do {
            let server = resolveMCPServerArg(from: call.args)
            let serverId = server.isEmpty ? nil : server
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
                "detail": "\(tools.count) tools discovered",
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    private func executeMCPDescribeTool(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }
        let toolName = (call.args["tool"] ?? call.args["mcp_tool"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolName.isEmpty else {
            return failure(
                "Missing tool name",
                errorCode: ToolRuntimeError.validation("tool missing").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }

        do {
            let serverArg = resolveMCPServerArg(from: call.args)
            let serverId = serverArg.isEmpty ? nil : serverArg
            let desc = try await mcpSessions.describeTool(serverId: serverId, toolName: toolName)
            guard let desc else {
                return failure(
                    "MCP tool not found",
                    errorCode: ToolRuntimeError.mcpUnavailable("MCP tool not found").errorCode,
                    startDate: startDate,
                    payload: ["is_mcp": "true"]
                )
            }
            return success([
                "title": "MCP describe \(desc.name)",
                "tool": "mcp_describe_tool",
                "server_id": desc.serverId,
                "mcp_tool": desc.name,
                "detail": desc.description,
                "output": truncate(desc.schema, maxBytes: context.policy.maxBashOutputBytes),
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    private func executeMCPHealth(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }
        let server = resolveMCPServerArg(from: call.args)
        let serverId = server.isEmpty ? nil : server

        let metrics = await mcpSessions.serverMetrics(serverId: serverId)
        if metrics.isEmpty {
            let states = await mcpSessions.health(serverId: server)
            let lines = states.keys.sorted().map { "\($0): \(states[$0] ?? "unknown")" }
            return success([
                "title": "MCP health",
                "tool": "mcp_health",
                "server_id": server,
                "output": lines.joined(separator: "\n"),
                "detail": "\(states.count) servers",
                "is_mcp": "true"
            ], startDate: startDate)
        }

        var lines: [String] = []
        for m in metrics {
            var caps: [String] = []
            if m.capabilities.supportsTools { caps.append("tools") }
            if m.capabilities.supportsResources { caps.append("resources") }
            if m.capabilities.supportsPrompts { caps.append("prompts") }
            if m.capabilities.supportsLogging { caps.append("logging") }
            if m.capabilities.supportsResourceSubscriptions { caps.append("subscriptions") }

            lines.append("""
            \(m.serverId) (\(m.serverName)):
              status: \(m.status)
              uptime: \(m.uptimeSeconds)s
              calls: \(m.totalCalls) total, \(m.failedCalls) failed
              latency: avg \(m.avgLatencyMs)ms, p95 \(m.p95LatencyMs)ms
              tools: \(m.toolCount), resources: \(m.resourceCount), prompts: \(m.promptCount)
              capabilities: [\(caps.joined(separator: ", "))]\(m.lastError.map { "\n  last_error: \($0)" } ?? "")
            """)
        }

        return success([
            "title": "MCP health (detailed)",
            "tool": "mcp_health",
            "server_id": serverId ?? "",
            "output": lines.joined(separator: "\n"),
            "detail": "\(metrics.count) servers",
            "is_mcp": "true"
        ], startDate: startDate)
    }

    private func executeMCPListServers(context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }
        let servers = await mcpSessions.listServers()
        let lines = servers.map { "\($0.id) (\($0.name)) [\($0.source)]" }
        return success([
            "title": "MCP servers",
            "tool": "mcp_list_servers",
            "output": lines.joined(separator: "\n"),
            "detail": "\(servers.count) servers",
            "is_mcp": "true"
        ], startDate: startDate)
    }

    private func executeMCPReconnect(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }
        let serverId = resolveMCPServerArg(from: call.args)
        guard !serverId.isEmpty else {
            return failure("Missing required server", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }
        do {
            try await mcpSessions.reconnect(serverId: serverId)
            return success([
                "title": "MCP reconnect",
                "tool": "mcp_reconnect",
                "server_id": serverId,
                "detail": "Connection re-established",
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    /// Execute a natively-registered MCP tool. The LLM calls it by function name;
    /// we route to the correct server and original tool name via the registry.
    private func executeNativeMCPTool(
        functionName: String,
        route: (serverId: String, toolName: String),
        call: ToolCall,
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }

        let metadataKeys: Set<String> = ["id", "name", "tool", "tool_name", "function", "function_name", "is_partial", "type", "status", "title", "detail", "output"]

        do {
            let result: (serverId: String, serverName: String, content: String, isError: Bool)
            if let rich = call.richArgs, !rich.isEmpty {
                var richFiltered = rich
                for key in metadataKeys { richFiltered.removeValue(forKey: key) }
                result = try await mcpSessions.callToolRich(
                    serverId: route.serverId,
                    toolName: route.toolName,
                    arguments: richFiltered,
                    timeoutMs: context.policy.mcpPerCallTimeoutMs,
                    idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
                )
            } else {
                var args = call.args
                for key in metadataKeys { args.removeValue(forKey: key) }
                result = try await mcpSessions.callTool(
                    serverId: route.serverId,
                    toolName: route.toolName,
                    arguments: args,
                    timeoutMs: context.policy.mcpPerCallTimeoutMs,
                    idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
                )
            }

            var payload: [String: String] = [
                "title": "\(result.serverName)/\(route.toolName)",
                "tool": functionName,
                "mcp_server": result.serverName,
                "server_id": result.serverId,
                "mcp_tool": route.toolName,
                "output": truncate(result.content, maxBytes: context.policy.maxBashOutputBytes),
                "mcp_latency_ms": "\(max(1, Int(Date().timeIntervalSince(startDate) * 1000)))",
                "is_mcp": "true"
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
                "mcp_tool": route.toolName,
                "server_id": route.serverId,
                "is_mcp": "true"
            ])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: [
                "mcp_tool": route.toolName,
                "server_id": route.serverId,
                "is_mcp": "true"
            ])
        }
    }

    private func executeMCPDirectToolFallback(
        toolName: String,
        call: ToolCall,
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult {
        do {
            let invocation = try buildMCPInvocation(call: call, fallbackToolName: toolName)
            let result = try await mcpSessions.callTool(
                serverId: invocation.serverId,
                toolName: invocation.toolName,
                arguments: invocation.arguments,
                timeoutMs: context.policy.mcpPerCallTimeoutMs,
                idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
            )
            return success([
                "title": "MCP fallback \(result.serverName)/\(invocation.toolName)",
                "tool": invocation.toolName,
                "server_id": result.serverId,
                "mcp_server": result.serverName,
                "mcp_tool": invocation.toolName,
                "output": truncate(result.content, maxBytes: context.policy.maxBashOutputBytes),
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            if err.errorCode == "mcp_unavailable" {
                return failure("Unsupported tool: \(toolName)", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
            }
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    // MARK: - MCP Advanced Tool Executors

    private func executeMCPBatch(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let callsJSON = call.args["calls"] ?? ""
        guard !callsJSON.isEmpty,
              let data = callsJSON.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return failure("Invalid 'calls' argument — expected JSON array of {server, tool, args}", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }

        let timeoutMs = Int(call.args["timeout_ms"] ?? "") ?? context.policy.mcpPerCallTimeoutMs
        var batchCalls: [(serverId: String?, toolName: String, arguments: [String: Any])] = []
        for item in parsed {
            let server = item["server"] as? String
            guard let tool = item["tool"] as? String, !tool.isEmpty else { continue }
            let args = (item["args"] as? [String: Any]) ?? [:]
            batchCalls.append((serverId: server, toolName: tool, arguments: args))
        }

        guard !batchCalls.isEmpty else {
            return failure("No valid calls in batch", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }

        let results = await mcpSessions.callToolsBatch(
            calls: batchCalls,
            timeoutMs: timeoutMs,
            idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
        )

        var outputLines: [String] = []
        var allOk = true
        for r in results {
            let status = r.isError ? "ERROR" : "OK"
            if r.isError { allOk = false }
            let tool = batchCalls[r.index].toolName
            let contentPreview = truncate(r.content, maxBytes: context.policy.maxBashOutputBytes / max(1, results.count))
            outputLines.append("[\(r.index)] \(tool) [\(status)]: \(contentPreview)")
        }

        return ToolResult(
            ok: allOk,
            payload: [
                "title": "MCP batch (\(results.count) calls)",
                "tool": "mcp_batch",
                "output": outputLines.joined(separator: "\n\n"),
                "detail": "\(results.count) calls, \(results.filter { !$0.isError }.count) succeeded",
                "is_mcp": "true"
            ],
            durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000))
        )
    }

    private func executeMCPListResources(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let server = resolveMCPServerArg(from: call.args)
        let serverId = server.isEmpty ? nil : server
        do {
            let resources = try await mcpSessions.listResources(serverId: serverId, idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds)
            let templates = try await mcpSessions.listResourceTemplates(serverId: serverId, idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds)

            var lines: [String] = []
            for r in resources {
                let mime = r.mimeType.map { " (\($0))" } ?? ""
                let desc = r.description.map { " — \($0)" } ?? ""
                lines.append("\(r.serverId)/\(r.uri): \(r.name)\(mime)\(desc)")
            }
            if !templates.isEmpty {
                lines.append("\n--- Resource Templates ---")
                for t in templates {
                    let desc = t.description.map { " — \($0)" } ?? ""
                    lines.append("\(t.serverId)/\(t.uriTemplate): \(t.name)\(desc)")
                }
            }

            return success([
                "title": "MCP resources",
                "tool": "mcp_list_resources",
                "server_id": serverId ?? "",
                "output": truncate(lines.joined(separator: "\n"), maxBytes: context.policy.maxBashOutputBytes),
                "detail": "\(resources.count) resources, \(templates.count) templates",
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    private func executeMCPReadResource(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let uri = (call.args["uri"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uri.isEmpty else {
            return failure("Missing required 'uri' argument", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }
        let server = resolveMCPServerArg(from: call.args)
        let serverId = server.isEmpty ? nil : server

        do {
            let content = try await mcpSessions.readResource(serverId: serverId, uri: uri, idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds)
            let output: String
            if let text = content.text {
                output = text
            } else if let blob = content.blob {
                output = "[binary \(content.mimeType ?? "application/octet-stream")] \(blob.count) bytes (base64)"
            } else {
                output = "(empty resource)"
            }
            return success([
                "title": "MCP resource \(uri)",
                "tool": "mcp_read_resource",
                "server_id": content.serverId,
                "mcp_server": content.serverName,
                "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
                "detail": content.mimeType ?? "unknown type",
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    private func executeMCPSubscribe(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let uri = (call.args["uri"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let server = resolveMCPServerArg(from: call.args)
        let action = (call.args["action"] ?? "subscribe").lowercased()

        guard !uri.isEmpty else {
            return failure("Missing required 'uri' argument", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }
        guard !server.isEmpty else {
            return failure("Missing required 'server' argument", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }

        do {
            if action == "unsubscribe" {
                await mcpSessions.unsubscribeResource(serverId: server, uri: uri)
                return success([
                    "title": "MCP unsubscribe",
                    "tool": "mcp_subscribe",
                    "server_id": server,
                    "detail": "Unsubscribed from \(uri)",
                    "is_mcp": "true"
                ], startDate: startDate)
            } else {
                try await mcpSessions.subscribeResource(serverId: server, uri: uri)
                return success([
                    "title": "MCP subscribe",
                    "tool": "mcp_subscribe",
                    "server_id": server,
                    "detail": "Subscribed to \(uri)",
                    "is_mcp": "true"
                ], startDate: startDate)
            }
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    private func executeMCPListPrompts(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let server = resolveMCPServerArg(from: call.args)
        let serverId = server.isEmpty ? nil : server

        do {
            let prompts = try await mcpSessions.listPrompts(serverId: serverId, idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds)
            let lines = prompts.map { p -> String in
                let args = p.arguments.isEmpty ? "" : " args: \(p.arguments.map { "\($0.name)\($0.required ? "*" : "")" }.joined(separator: ", "))"
                let desc = p.description.map { " — \($0)" } ?? ""
                return "\(p.serverId)/\(p.name)\(desc)\(args)"
            }
            return success([
                "title": "MCP prompts",
                "tool": "mcp_list_prompts",
                "server_id": serverId ?? "",
                "output": truncate(lines.joined(separator: "\n"), maxBytes: context.policy.maxBashOutputBytes),
                "detail": "\(prompts.count) prompts discovered",
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    private func executeMCPGetPrompt(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let promptName = (call.args["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptName.isEmpty else {
            return failure("Missing required 'name' argument", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }
        let server = resolveMCPServerArg(from: call.args)
        let serverId = server.isEmpty ? nil : server

        var promptArgs: [String: String] = [:]
        if let argsJSON = call.args["args"], !argsJSON.isEmpty,
           let data = argsJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            promptArgs = parsed
        }

        do {
            let result = try await mcpSessions.getPrompt(serverId: serverId, name: promptName, arguments: promptArgs, idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds)
            var output = ""
            if let desc = result.description {
                output += "Description: \(desc)\n\n"
            }
            for msg in result.messages {
                output += "[\(msg.role)]\n\(msg.content)\n\n"
            }
            return success([
                "title": "MCP prompt \(promptName)",
                "tool": "mcp_get_prompt",
                "server_id": result.serverId,
                "mcp_server": result.serverName,
                "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
                "detail": "\(result.messages.count) messages",
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    private func executeMCPLogs(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let server = resolveMCPServerArg(from: call.args)
        let serverId = server.isEmpty ? nil : server
        let action = (call.args["action"] ?? "read").lowercased()

        switch action {
        case "set_level":
            let level = (call.args["level"] ?? "info").lowercased()
            guard let sid = serverId, !sid.isEmpty else {
                return failure("'server' is required for set_level action", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
            }
            do {
                try await mcpSessions.setLogLevel(serverId: sid, level: level)
                return success([
                    "title": "MCP log level set",
                    "tool": "mcp_logs",
                    "server_id": sid,
                    "detail": "Log level set to \(level)",
                    "is_mcp": "true"
                ], startDate: startDate)
            } catch let err as ToolRuntimeError {
                return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
            } catch {
                return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
            }
        case "clear":
            await mcpSessions.logStore.clear(serverId: serverId)
            return success([
                "title": "MCP logs cleared",
                "tool": "mcp_logs",
                "server_id": serverId ?? "",
                "detail": "Log buffer cleared",
                "is_mcp": "true"
            ], startDate: startDate)
        default:
            let severity = call.args["severity"] ?? "info"
            let limit = Int(call.args["limit"] ?? "50") ?? 50
            let entries = await mcpSessions.logStore.logs(serverId: serverId, severity: severity, limit: limit)
            if entries.isEmpty {
                return success([
                    "title": "MCP logs",
                    "tool": "mcp_logs",
                    "server_id": serverId ?? "",
                    "output": "(no log entries)",
                    "detail": "0 entries",
                    "is_mcp": "true"
                ], startDate: startDate)
            }
            let df = ISO8601DateFormatter()
            let lines = entries.map { e in
                let ts = df.string(from: e.timestamp)
                let logger = e.logger.map { " [\($0)]" } ?? ""
                return "\(ts) [\(e.level.uppercased())]\(logger) \(e.serverId): \(e.message)"
            }
            return success([
                "title": "MCP logs",
                "tool": "mcp_logs",
                "server_id": serverId ?? "",
                "output": truncate(lines.joined(separator: "\n"), maxBytes: context.policy.maxBashOutputBytes),
                "detail": "\(entries.count) entries",
                "is_mcp": "true"
            ], startDate: startDate)
        }
    }

    private func executeMCPRestartServer(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let serverId = resolveMCPServerArg(from: call.args)
        guard !serverId.isEmpty else {
            return failure("Missing required 'server' argument", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }
        do {
            try await mcpSessions.restartServer(serverId: serverId)
            return success([
                "title": "MCP restart",
                "tool": "mcp_restart_server",
                "server_id": serverId,
                "detail": "Server fully restarted and reconnected",
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
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
        let allLines = rawContent.components(separatedBy: "\n")

        let offsetLine = max(1, Int(call.args["offset"] ?? "1") ?? 1)
        let startIndex = max(0, offsetLine - 1)
        let requestedLimit = Int(call.args["limit"] ?? "") ?? 0
        let endIndex: Int = {
            guard requestedLimit > 0 else { return allLines.count }
            return min(allLines.count, startIndex + requestedLimit)
        }()

        let selectedLines: ArraySlice<String>
        if startIndex >= allLines.count {
            selectedLines = []
        } else {
            selectedLines = allLines[startIndex..<endIndex]
        }

        let digitCount = max(1, String(allLines.count).count)
        let numberedLines = selectedLines.enumerated().map { idx, line in
            let num = String(startIndex + idx + 1)
            let padding = String(repeating: " ", count: max(0, digitCount - num.count))
            return "\(padding)\(num)│\(line)"
        }
        let content = numberedLines.joined(separator: "\n")

        return success([
            "title": "Read \(path)",
            "path": path,
            "output": content,
            "detail": "\(selectedLines.count) lines"
        ], startDate: startDate)
    }

    private func executeReadRange(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let path = try resolveRequiredPath(call.args["path"], context: context)
        let startLine = max(1, Int(call.args["start"] ?? call.args["start_line"] ?? "1") ?? 1)
        let endLineRaw = Int(call.args["end"] ?? call.args["end_line"] ?? "0") ?? 0
        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let lines = content.components(separatedBy: .newlines)
        let endLine = endLineRaw > 0 ? min(lines.count, endLineRaw) : min(lines.count, startLine + 200)
        if startLine > endLine || startLine > lines.count {
            throw ToolRuntimeError.validation("Invalid line range")
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
        let excludedSet = Set(context.workspaceContext.excludedPaths)
        let filtered = entries.filter { entry in
            let name = entry.lastPathComponent
            if excludedSet.contains(name) { return false }
            if excludedSet.contains(entry.path) { return false }
            for ws in context.workspaceContext.workspacePaths {
                let rel = entry.path.replacingOccurrences(of: ws.path + "/", with: "")
                if excludedSet.contains(rel) { return false }
            }
            return true
        }
        let sorted = filtered
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(maxEntries)
            .map { entry -> String in
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return isDir ? "\(entry.lastPathComponent)/" : entry.lastPathComponent
            }
        return success([
            "title": "List dir \(path)",
            "path": path,
            "detail": "\(sorted.count) entries",
            "output": sorted.joined(separator: "\n")
        ], startDate: startDate)
    }

    private func executeWrite(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        guard let pathArg = call.args["path"] else {
            throw ToolRuntimeError.validation("Missing path")
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
            return failure("query is required", errorCode: "validation", startDate: startDate)
        }

        // Prefer index-powered search if available (supports all languages)
        if let indexTools {
            let events = await indexTools.execute(
                toolName: "codebase_search",
                args: call.args,
                callId: call.id,
                workspacePaths: preferredWorkspacePaths(for: context),
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
            throw ToolRuntimeError.validation("JSON cannot be read")
        }
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ToolRuntimeError.validation("Invalid JSON")
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
            throw ToolRuntimeError.validation("patch JSON is required")
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
            throw ToolRuntimeError.validation("write_json supports only JSON object root")
        }
        if let patchDict = patchObj as? [String: Any] {
            for (k, v) in patchDict { merged[k] = v }
        } else {
            throw ToolRuntimeError.validation("patch must be a JSON object")
        }
        let output = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: URL(fileURLWithPath: path), options: .atomic)
        return success([
            "title": "Write JSON \(path)",
            "path": path,
            "detail": "Patch applied",
            "output": String(data: output, encoding: .utf8) ?? ""
        ], startDate: startDate)
    }

    private func executeWorkspaceStats(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let scope = (call.args["path"] ?? ".").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPath: String
        do {
            resolvedPath = try resolveRequiredPath(scope, context: context)
        } catch {
            return failure("Invalid path: \(scope)", errorCode: "validation", startDate: startDate)
        }
        let statsURL = URL(fileURLWithPath: resolvedPath)
        let excludedSet = Set(context.workspaceContext.excludedPaths)

        let stats = await Task.detached(priority: .utility) {
            var fileCount = 0
            var dirCount = 0
            var totalBytes: Int64 = 0
            let fm = FileManager.default

            if let enumerator = fm.enumerator(
                at: statsURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
                while let itemURL = enumerator.nextObject() as? URL {
                    let name = itemURL.lastPathComponent
                    if excludedSet.contains(name) {
                        enumerator.skipDescendants()
                        continue
                    }
                    guard let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else { continue }
                    if values.isDirectory == true {
                        dirCount += 1
                    } else {
                        fileCount += 1
                        totalBytes += Int64(values.fileSize ?? 0)
                    }
                }
            }
            return (fileCount, dirCount, totalBytes)
        }.value

        let sizeStr: String
        if stats.2 > 1_048_576 {
            sizeStr = String(format: "%.1f MB", Double(stats.2) / 1_048_576.0)
        } else if stats.2 > 1024 {
            sizeStr = String(format: "%.1f KB", Double(stats.2) / 1024.0)
        } else {
            sizeStr = "\(stats.2) bytes"
        }

        return success([
            "title": "Workspace stats",
            "path": resolvedPath,
            "detail": "\(stats.0) files, \(stats.1) dirs, \(sizeStr)",
            "output": "files: \(stats.0)\ndirs: \(stats.1)\nsize: \(sizeStr)\nbytes: \(stats.2)"
        ], startDate: startDate)
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
            return failure("unsupported manager: \(manager)", errorCode: "validation", startDate: startDate)
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
            return failure("path is required", errorCode: "validation", startDate: startDate)
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

    private static let longRunningPatterns: [String] = [
        "npm run", "npm start", "npm test", "yarn ", "pnpm ",
        "swift build", "swift test", "swift run",
        "cargo build", "cargo run", "cargo test",
        "make", "cmake", "gradle",
        "python ", "python3 ", "node ",
        "docker ", "kubectl ",
        "xcodebuild", "fastlane",
        "serve", "watch", "dev"
    ]

    private func isLongRunningCommand(_ command: String) -> Bool {
        let lower = command.lowercased()
        return Self.longRunningPatterns.contains(where: { lower.contains($0) })
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

            if isLongRunningCommand(command), let bridge = terminalBridge {
                let label = "Agent: \(command.prefix(40))"
                let result = await bridge.executeInTerminal(
                    command: command,
                    cwd: cwd.path,
                    label: label
                )
                let output = truncate(String(result.output.prefix(maxOutputBytes)), maxBytes: maxOutputBytes)
                if result.exitCode == 0 {
                    return success([
                        "title": title,
                        "command": command,
                        "cwd": cwd.path,
                        "output": output,
                        "ran_in_terminal": "true"
                    ], startDate: startDate)
                }
                return failure(
                    "exit \(result.exitCode): \(truncate(output, maxBytes: 3_000))",
                    errorCode: "transport",
                    startDate: startDate,
                    payload: [
                        "title": title,
                        "command": command,
                        "cwd": cwd.path,
                        "output": output,
                        "ran_in_terminal": "true"
                    ]
                )
            }

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
                    throw ToolRuntimeError.transport("No response from process")
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

    // MARK: - Read Terminal

    private func executeReadTerminal(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = terminalBridge else {
            return failure(
                "Terminal bridge not available",
                errorCode: "transport",
                startDate: startDate
            )
        }
        let sessionId = call.args["session_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastN = max(500, min(32_000, Int(call.args["last_n"] ?? "8000") ?? 8_000))
        let emptySessionId: String? = (sessionId?.isEmpty == true) ? nil : sessionId

        let output: String
        if call.args["all_sessions"] == "true" {
            output = await bridge.allSessionsSummary(lastN: lastN)
        } else {
            output = await bridge.readTerminalOutput(sessionId: emptySessionId, lastN: lastN)
        }

        if output.isEmpty {
            return success(["output": "(no terminal output)", "detail": "empty"], startDate: startDate)
        }
        return success(["output": output, "detail": "\(output.count) chars"], startDate: startDate)
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

    // MARK: - Browser Tools

    private func executeBrowserNavigate(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = browserBridge else {
            return failure("Browser bridge not available", errorCode: "transport", startDate: startDate)
        }
        let url = (call.args["url"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            return failure("url is required", errorCode: "validation", startDate: startDate)
        }
        await bridge.navigate(to: url)
        try? await Task.sleep(for: .milliseconds(500))
        let currentURL = await bridge.getCurrentURL() ?? url
        let title = await bridge.getPageTitle() ?? ""
        return success([
            "title": "Navigated to \(currentURL)",
            "detail": title.isEmpty ? currentURL : "\(title) — \(currentURL)",
            "url": currentURL,
            "output": "Successfully navigated to \(currentURL)\(title.isEmpty ? "" : "\nPage title: \(title)")"
        ], startDate: startDate)
    }

    private func executeBrowserScreenshot(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = browserBridge else {
            return failure("Browser bridge not available", errorCode: "transport", startDate: startDate)
        }
        guard let pngData = await bridge.takeScreenshot() else {
            return failure("Failed to capture screenshot", errorCode: "runtime", startDate: startDate)
        }
        let base64 = pngData.base64EncodedString()
        let currentURL = await bridge.getCurrentURL() ?? ""
        return success([
            "title": "Screenshot captured",
            "detail": "\(pngData.count / 1024)KB PNG",
            "url": currentURL,
            "output": "data:image/png;base64,\(base64)"
        ], startDate: startDate)
    }

    private func executeBrowserConsoleLogs(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = browserBridge else {
            return failure("Browser bridge not available", errorCode: "transport", startDate: startDate)
        }
        let levelFilter = call.args["level"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastN = Int(call.args["last_n"] ?? "100") ?? 100
        let logs = await bridge.getConsoleLogs(level: levelFilter)
        let lines = logs.split(separator: "\n")
        let recentLogs = lines.suffix(lastN).joined(separator: "\n")
        return success([
            "title": "Console logs",
            "detail": "\(lines.count) entries\(levelFilter.map { " (filter: \($0))" } ?? "")",
            "output": recentLogs.isEmpty ? "(no console logs)" : recentLogs
        ], startDate: startDate)
    }

    private func executeBrowserClick(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = browserBridge else {
            return failure("Browser bridge not available", errorCode: "transport", startDate: startDate)
        }
        let selector = (call.args["selector"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selector.isEmpty else {
            return failure("selector is required", errorCode: "validation", startDate: startDate)
        }
        let clicked = await bridge.click(selector: selector)
        if clicked {
            return success([
                "title": "Clicked element",
                "detail": selector,
                "output": "Successfully clicked element matching '\(selector)'"
            ], startDate: startDate)
        } else {
            return failure(
                "Element not found: \(selector)",
                errorCode: "not_found",
                startDate: startDate,
                payload: ["title": "Click failed", "detail": selector]
            )
        }
    }

    private func executeBrowserType(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = browserBridge else {
            return failure("Browser bridge not available", errorCode: "transport", startDate: startDate)
        }
        let selector = (call.args["selector"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = call.args["text"] ?? ""
        guard !selector.isEmpty else {
            return failure("selector is required", errorCode: "validation", startDate: startDate)
        }
        let typed = await bridge.type(selector: selector, text: text)
        if typed {
            return success([
                "title": "Typed text",
                "detail": "'\(text.prefix(40))' into \(selector)",
                "output": "Successfully typed text into element matching '\(selector)'"
            ], startDate: startDate)
        } else {
            return failure(
                "Element not found: \(selector)",
                errorCode: "not_found",
                startDate: startDate,
                payload: ["title": "Type failed", "detail": selector]
            )
        }
    }

    private func executeBrowserEvaluateJS(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = browserBridge else {
            return failure("Browser bridge not available", errorCode: "transport", startDate: startDate)
        }
        let script = (call.args["script"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else {
            return failure("script is required", errorCode: "validation", startDate: startDate)
        }
        let result = await bridge.evaluateJS(script)
        return success([
            "title": "Evaluated JS",
            "detail": "\(script.prefix(60))",
            "output": result ?? "undefined"
        ], startDate: startDate)
    }

    private func executeBrowserGetContent(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = browserBridge else {
            return failure("Browser bridge not available", errorCode: "transport", startDate: startDate)
        }
        guard let content = await bridge.getPageContent() else {
            return failure("Failed to get page content", errorCode: "runtime", startDate: startDate)
        }
        let truncated = content.count > 100_000 ? String(content.prefix(100_000)) + "\n... (truncated)" : content
        let currentURL = await bridge.getCurrentURL() ?? ""
        return success([
            "title": "Page content",
            "url": currentURL,
            "detail": "\(content.count) chars",
            "output": truncated
        ], startDate: startDate)
    }

    private func validate(call: ToolCall, normalizedName: String) throws {
        switch normalizedName {
        case "read", "write", "edit", "read_range", "list_dir", "read_json", "write_json", "tail_log",
             "str_replace", "create_file":
            let path = call.args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if path.isEmpty && normalizedName != "list_dir" {
                throw ToolRuntimeError.validation("path is required")
            }
        case "grep":
            let query = (call.args["query"] ?? call.args["pattern"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                throw ToolRuntimeError.validation("pattern (or query) is required")
            }
        case "find_symbol", "find_references":
            let query = (call.args["query"] ?? call.args["name"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                throw ToolRuntimeError.validation("query is required")
            }
        case "find_files":
            let query = (call.args["query"] ?? call.args["pattern"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                throw ToolRuntimeError.validation("pattern (or query) is required")
            }
        case "web_search", "search_symbols", "codebase_search", "rename_symbol", "semantic_search":
            let query = call.args["query"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if query.isEmpty {
                throw ToolRuntimeError.validation("query is required")
            }
        case "web_fetch":
            let url = call.args["url"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if url.isEmpty {
                throw ToolRuntimeError.validation("url is required")
            }
        case "browser_navigate":
            let url = call.args["url"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if url.isEmpty {
                throw ToolRuntimeError.validation("url is required")
            }
        case "browser_click":
            let selector = call.args["selector"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if selector.isEmpty {
                throw ToolRuntimeError.validation("selector is required")
            }
        case "browser_type":
            let selector = call.args["selector"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = call.args["text"] ?? ""
            if selector.isEmpty { throw ToolRuntimeError.validation("selector is required") }
            if text.isEmpty { throw ToolRuntimeError.validation("text is required") }
        case "browser_evaluate_js":
            let script = call.args["script"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if script.isEmpty {
                throw ToolRuntimeError.validation("script is required")
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
        case "mcp_reconnect", "mcp_restart_server":
            let server = resolveMCPServerArg(from: call.args)
            if server.isEmpty {
                throw ToolRuntimeError.validation("server is required")
            }
        case "mcp", "mcp_call":
            _ = try buildMCPInvocation(call: call)
        case "mcp_batch":
            if (call.args["calls"] ?? "").isEmpty {
                throw ToolRuntimeError.validation("'calls' is required — JSON array of {server, tool, args}")
            }
        case "mcp_read_resource":
            if (call.args["uri"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ToolRuntimeError.validation("'uri' is required")
            }
        case "mcp_subscribe":
            if (call.args["uri"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ToolRuntimeError.validation("'uri' is required")
            }
            if resolveMCPServerArg(from: call.args).isEmpty {
                throw ToolRuntimeError.validation("'server' is required for subscribe")
            }
        case "mcp_get_prompt":
            if (call.args["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ToolRuntimeError.validation("'name' is required")
            }
        default:
            break
        }
    }

    private func resolveRequiredPath(_ rawPath: String?, context: ToolExecutionContext) throws -> String {
        let allPaths = context.workspaceContext.workspacePaths.map(\.path)
        let preferredRoot = context.workspaceContext.activeRootPath
        guard let path = resolvePath(rawPath, workspacePaths: allPaths, preferredRoot: preferredRoot, sandboxMode: context.policy.sandboxMode) else {
            throw ToolRuntimeError.sandboxViolation("Path is not allowed by sandbox policy")
        }
        return path
    }

    private func resolvePath(_ rawPath: String?, workspacePaths: [String], preferredRoot: String?, sandboxMode: String) -> String? {
        let raw = (rawPath ?? ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let isAbsolute = (raw as NSString).isAbsolutePath

        if isAbsolute {
            let resolvedURL = URL(fileURLWithPath: raw).standardizedFileURL
            if sandboxMode == "danger-full-access" {
                return resolvedURL.path
            }
            for ws in workspacePaths {
                let wsURL = URL(fileURLWithPath: ws).standardizedFileURL
                let wsPath = wsURL.path.hasSuffix("/") ? wsURL.path : wsURL.path + "/"
                if resolvedURL.path == wsURL.path || resolvedURL.path.hasPrefix(wsPath) {
                    return resolvedURL.path
                }
            }
            return nil
        }

        let roots: [String]
        if let preferred = preferredRoot, workspacePaths.contains(preferred) {
            roots = [preferred] + workspacePaths.filter { $0 != preferred }
        } else {
            roots = workspacePaths
        }

        for ws in roots {
            let wsURL = URL(fileURLWithPath: ws).standardizedFileURL
            let resolvedURL = wsURL.appendingPathComponent(raw).standardizedFileURL
            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                if sandboxMode == "danger-full-access" {
                    return resolvedURL.path
                }
                let wsPath = wsURL.path.hasSuffix("/") ? wsURL.path : wsURL.path + "/"
                if resolvedURL.path == wsURL.path || resolvedURL.path.hasPrefix(wsPath) {
                    return resolvedURL.path
                }
            }
        }

        let primaryURL = URL(fileURLWithPath: roots[0]).standardizedFileURL
        let resolvedURL = primaryURL.appendingPathComponent(raw).standardizedFileURL
        if sandboxMode == "danger-full-access" {
            return resolvedURL.path
        }
        let primaryPath = primaryURL.path.hasSuffix("/") ? primaryURL.path : primaryURL.path + "/"
        if resolvedURL.path == primaryURL.path || resolvedURL.path.hasPrefix(primaryPath) {
            return resolvedURL.path
        }
        return nil
    }

    private func validateShell(command: String, policy: ToolRuntimePolicy) throws {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ToolRuntimeError.validation("Empty command")
        }
        let lower = trimmed.lowercased()

        if !policy.allowDangerousShellPatterns {
            let blockedPatterns = [
                "rm -rf /", ":(){ :|:& };:", "sudo ", "> /dev/sd", "mkfs", "dd if=", "shutdown", "reboot", "kill -9 1"
            ]
            for pattern in blockedPatterns where lower.contains(pattern) {
                throw ToolRuntimeError.sandboxViolation("Command blocked by strict policy")
            }

            if lower.contains(" > /") || lower.contains(" >> /") {
                throw ToolRuntimeError.sandboxViolation("Absolute redirection blocked in strict mode")
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
                throw ToolRuntimeError.sandboxViolation("Command not allowed in strict mode: \(head)")
            }
        }
    }

    private func buildBasePayload(call: ToolCall, normalizedName: String) -> [String: String] {
        var payload: [String: String] = [
            "tool_call_id": call.id,
            "tool": normalizedName,
            "status": "started"
        ]
        let mcpLikeInvocation = canFallbackToMCP(toolName: normalizedName, call: call)
        if mcpLikeInvocation {
            payload["is_mcp"] = "true"
        }
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
        let requestedMCPTool = (call.args["tool"] ?? call.args["mcp_tool"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !requestedMCPTool.isEmpty {
            payload["mcp_tool"] = requestedMCPTool
        }
        if let url = call.args["url"], !url.isEmpty {
            payload["url"] = url
        }
        let server = resolveMCPServerArg(from: call.args)
        if !server.isEmpty {
            payload["server_id"] = server
            payload["mcp_server"] = server
        }
        if let swarmId = call.swarmId, !swarmId.isEmpty {
            payload["swarm_id"] = swarmId
            payload["group_id"] = "swarm-\(swarmId)"
        }
        return payload
    }

    private func startEventTypeForTool(name: String, payload: [String: String]) -> String {
        if payload["is_mcp"] == "true" {
            return "mcp_tool_call"
        }
        switch name {
        case "edit", "write", "str_replace", "create_file", "parallel_apply", "regex_replace",
             "rename_symbol", "find_and_replace_all", "undo_edit":
            return "file_change"
        case "bash":
            return "command_execution"
        case "web_search":
            return "web_search_started"
        case "web_fetch":
            return "web_fetch_started"
        case "browser_navigate", "browser_screenshot", "browser_console_logs",
             "browser_click", "browser_type", "browser_evaluate_js", "browser_get_content":
            return "browser_action_started"
        default:
            return "read_batch_started"
        }
    }

    private func eventTypeForTool(name: String, ok: Bool, payload: [String: String]) -> String {
        if payload["is_mcp"] == "true" {
            return ok ? "mcp_tool_call" : "tool_execution_error"
        }
        switch name {
        case "read", "glob", "grep", "read_range", "list_dir", "git_diff", "search_symbols",
             "run_tests", "build_project", "list_processes", "read_json", "write_json",
             "workspace_stats", "dependency_audit", "tail_log",
             "codebase_search", "find_symbol", "list_symbols", "find_references",
             "project_structure", "file_outline", "find_files", "codebase_stats",
             "dependency_graph", "list_types", "list_tests", "index_status", "reindex",
             "diagnostics", "attempt_completion",
             "run_single_test",
             "semantic_search", "read_lints", "debug_context",
             "batch_read", "diff_files", "git_status", "git_show", "code_context",
             "related_files", "git_log_search":
            return ok ? "read_batch_completed" : "tool_execution_error"
        case "debug_log", "debug_query", "debug_session", "debug_hypothesize", "debug_mark", "debug_clean",
             "debug_trace_analyze", "debug_instrument", "debug_timeline", "debug_snapshot", "debug_test_check":
            return ok ? name : "tool_execution_error"
        case "edit", "write", "str_replace", "create_file", "parallel_apply", "regex_replace",
             "rename_symbol", "find_and_replace_all", "undo_edit", "apply_diff":
            return ok ? "file_change" : "tool_execution_error"
        case "bash":
            return ok ? "command_execution" : "tool_execution_error"
        case "web_search":
            return ok ? "web_search_completed" : "web_search_failed"
        case "web_fetch":
            return ok ? "web_fetch_completed" : "web_fetch_failed"
        case "browser_navigate", "browser_screenshot", "browser_console_logs",
             "browser_click", "browser_type", "browser_evaluate_js", "browser_get_content":
            return ok ? "browser_action_completed" : "browser_action_failed"
        default:
            return ok ? "command_execution" : "tool_execution_error"
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

    private func parseDebugDataArg(_ raw: String?) -> [String: String] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var out: [String: String] = [:]
            for (key, value) in json { out[key] = "\(value)" }
            return out
        }
        var out: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                out[kv[0].trimmingCharacters(in: .whitespacesAndNewlines)] = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return out
    }

    private func normalizeHypothesisStatus(_ status: String, fallback: String) -> String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "proposed", "investigating", "confirmed", "rejected":
            return status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        default:
            return fallback
        }
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
        let indexTools = await ensureIndexTools(for: context)
        let normalizedArgs = normalizedArgsForIndexTool(name: name, args: call.args)
        let events = await indexTools.execute(
            toolName: name,
            args: normalizedArgs,
            callId: call.id,
            workspacePaths: preferredWorkspacePaths(for: context),
            excludedPaths: excludedPaths
        )
        return toolResultFromIndexEvents(events, startDate: startDate)
    }

    private func normalizedArgsForIndexTool(name: String, args: [String: String]) -> [String: String] {
        var normalized = args

        switch name {
        case "find_symbol", "find_references":
            if (normalized["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let legacyName = normalized["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !legacyName.isEmpty {
                normalized["query"] = legacyName
            }
        case "find_files":
            if (normalized["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let pattern = normalized["pattern"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pattern.isEmpty {
                normalized["query"] = pattern
            }
            if (normalized["filePattern"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let pathScope = normalized["path"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pathScope.isEmpty {
                normalized["filePattern"] = normalizePathScopeAsFilePattern(pathScope)
            }
        case "codebase_search":
            if (normalized["filePattern"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let path = normalized["path"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                normalized["filePattern"] = normalizePathScopeAsFilePattern(path)
            }
        default:
            break
        }

        return normalized
    }

    private func normalizePathScopeAsFilePattern(_ rawPathScope: String) -> String {
        var normalized = rawPathScope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        if normalized == "." { return "" }
        if normalized.hasPrefix("./") {
            normalized = String(normalized.dropFirst(2))
        }
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        guard !normalized.isEmpty, normalized != "." else { return "" }
        return normalized
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
        let query = (call.args["query"] ?? call.args["pattern"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawScope = (call.args["pathScope"] ?? call.args["path"] ?? ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let scopeParts = rawScope
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let allWorkspacePaths = context.workspaceContext.workspacePaths.map(\.path)
        let primaryWorkspace = context.workspaceContext.workspacePath.path
        let scopes: [String] = {
            if scopeParts.isEmpty || (scopeParts.count == 1 && scopeParts[0] == ".") {
                return allWorkspacePaths.isEmpty ? ["."] : allWorkspacePaths
            }
            var out: [String] = []
            var seen = Set<String>()
            for item in scopeParts where seen.insert(item).inserted {
                let isAbsolute = (item as NSString).isAbsolutePath
                if isAbsolute {
                    out.append(item)
                } else {
                    for root in allWorkspacePaths {
                        out.append((root as NSString).appendingPathComponent(item))
                    }
                }
            }
            return out
        }()
        let fileType = call.args["fileType"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let globPattern = call.args["glob"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let contextLines = Int(call.args["context_lines"] ?? "") ?? 2
        let caseSensitive = (call.args["case_sensitive"] ?? "false").lowercased() == "true"
        let multiline = (call.args["multiline"] ?? "false").lowercased() == "true"
        let outputModeRaw = (call.args["output_mode"] ?? "content").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let outputMode: String = {
            switch outputModeRaw {
            case "files_only", "files", "paths":
                return "files_only"
            case "count":
                return "count"
            default:
                return "content"
            }
        }()
        let shouldUseContentMode = outputMode == "content"

        // If query looks like a symbol name (no regex chars) and index is available, try index first.
        // Use a short timeout (200ms) to avoid blocking grep when the index is still building.
        if shouldUseContentMode, let indexTools, let codebaseIndex, !query.isEmpty, !containsRegexChars(query) {
            let indexReady = await codebaseIndex.waitUntilReady(timeoutMs: 200)
            if indexReady {
                let indexEvents = await indexTools.execute(
                    toolName: "codebase_search",
                    args: ["query": query, "kind": "all"],
                    callId: call.id,
                    workspacePaths: preferredWorkspacePaths(for: context),
                    excludedPaths: excludedPaths
                )
                let indexResult = toolResultFromIndexEvents(indexEvents, startDate: startDate)
                if indexResult.ok,
                   let output = indexResult.payload["output"],
                    !output.isEmpty,
                    !output.contains("No symbols found") {
                    var payload = indexResult.payload
                    payload["title"] = "Grep \(query) (index + rg)"
                    payload["pathScope"] = (rawScope.isEmpty || rawScope == ".") ? scopes.joined(separator: ",") : rawScope
                    return ToolResult(ok: true, payload: payload, durationMs: indexResult.durationMs)
                }
            } else {
                Self.logger.debug("executeGrep: index not ready within 200ms, skipping to ripgrep for '\(query, privacy: .public)'")
            }
        }

        let maxContext = min(max(contextLines, 0), 10)
        var searchOutput = ""
        var searchError = ""
        var usedFallback = false

        // Primary: ripgrep — when multiple scopes (roots), search each; cwd uses first scope
        let rgCwd = scopes.first ?? primaryWorkspace
        var rgArgs = ["/usr/bin/env", "rg", "-n", "--no-heading", "--max-count", "200"]
        if !caseSensitive { rgArgs.append("-i") }
        if multiline { rgArgs.append("-U") }
        if !fileType.isEmpty { rgArgs.append(contentsOf: ["--type", fileType]) }
        if !globPattern.isEmpty { rgArgs.append(contentsOf: ["--glob", globPattern]) }
        if shouldUseContentMode, maxContext > 0 { rgArgs.append(contentsOf: ["-C", "\(maxContext)"]) }
        if outputMode == "files_only" { rgArgs.append("-l") }
        if outputMode == "count" { rgArgs.append("--count") }
        rgArgs.append(query)
        rgArgs.append(contentsOf: scopes)
        rgArgs.append(contentsOf: ["--glob", "!.build", "--glob", "!node_modules", "--glob", "!.git"])

        let (rgOut, rgErr, rgExit) = await shellExec(
            args: rgArgs,
            cwd: rgCwd,
            timeout: context.policy.timeoutMs
        )
        searchOutput = rgOut
        searchError = rgErr

        // Fallback: grep when rg is not available.
        let rgMissing = rgExit == 127
            || rgErr.lowercased().contains("command not found")
            || rgErr.lowercased().contains("no such file or directory")
        if rgMissing {
            usedFallback = true
            var grepArgs = ["/usr/bin/env", "grep", "-RIn"]
            if !caseSensitive { grepArgs.append("-i") }
            if shouldUseContentMode, maxContext > 0 { grepArgs.append(contentsOf: ["-C", "\(maxContext)"]) }
            if outputMode == "files_only" { grepArgs.append("-l") }
            if outputMode == "count" { grepArgs.append("-c") }
            grepArgs.append(query)
            grepArgs.append(contentsOf: scopes)

            let (grepOut, grepErr, _) = await shellExec(
                args: grepArgs,
                cwd: rgCwd,
                timeout: context.policy.timeoutMs
            )
            searchOutput = grepOut
            searchError = grepErr
        }

        let durationMs = max(1, Int(Date().timeIntervalSince(startDate) * 1000))
        let trimmedOutput = searchOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        // If both engines are unavailable or failed unexpectedly, report transport failure.
        if trimmedOutput.isEmpty, usedFallback, searchError.lowercased().contains("not found") {
            return failure(
                "Text search tools are unavailable (rg/grep not found)",
                errorCode: "transport",
                startDate: startDate,
                payload: [
                    "title": "Grep \(query)",
                    "pathScope": (rawScope.isEmpty || rawScope == ".") ? scopes.joined(separator: ",") : rawScope,
                ]
            )
        }

        // No matches is a successful search with zero results.
        if trimmedOutput.isEmpty {
            return ToolResult(ok: true, payload: [
                "title": "Grep \(query)",
                "query": query,
                "detail": "No matches found",
                "output": "",
                "count": "0",
                "previewLines": "",
                "output_mode": outputMode,
                "pathScope": (rawScope.isEmpty || rawScope == ".") ? scopes.joined(separator: ",") : rawScope,
            ], durationMs: durationMs)
        }

        let renderedOutput: String
        let matchCount: Int
        let previewLines: String
        let detail: String

        switch outputMode {
        case "files_only":
            let files = trimmedOutput
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            renderedOutput = files.joined(separator: "\n")
            matchCount = files.count
            previewLines = files.prefix(8).joined(separator: "\n")
            detail = "\(matchCount) files matched"
        case "count":
            let rows = trimmedOutput
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let total = rows.reduce(0) { partial, row in
                guard let tail = row.split(separator: ":").last,
                      let value = Int(tail.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    return partial
                }
                return partial + value
            }
            renderedOutput = rows.joined(separator: "\n")
            matchCount = max(0, total)
            previewLines = rows.prefix(8).joined(separator: "\n")
            detail = "\(matchCount) total matches"
        default:
            let ranked = rankGrepResults(searchOutput, query: query)
            let matchLines = extractSearchMatchLines(ranked, limit: 500)
            renderedOutput = ranked
            matchCount = matchLines.count
            previewLines = matchLines.prefix(8).joined(separator: "\n")
            detail = "\(matchCount) matches"
        }

        let pathScopeForPayload = (rawScope.isEmpty || rawScope == ".") ? scopes.joined(separator: ",") : rawScope
        return ToolResult(ok: true, payload: [
            "title": "Grep \(query)",
            "query": query,
            "detail": detail,
            "output": truncate(renderedOutput, maxBytes: context.policy.maxBashOutputBytes),
            "count": "\(matchCount)",
            "previewLines": previewLines,
            "output_mode": outputMode,
            "pathScope": pathScopeForPayload,
            "glob": globPattern,
        ], durationMs: durationMs)
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

    private func extractSearchMatchLines(_ output: String, limit: Int = .max) -> [String] {
        var matches: [String] = []
        var seen = Set<String>()

        for rawLine in output.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = rawLine.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count >= 3, let lineNumber = Int(parts[1]) else { continue }
            let preview = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = "\(parts[0]):\(lineNumber):\(preview)"
            guard seen.insert(normalized).inserted else { continue }
            matches.append(normalized)
            if matches.count >= limit { break }
        }

        return matches
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
                workspacePaths: preferredWorkspacePaths(for: context),
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
        let allWorkspacePaths = context.workspaceContext.workspacePaths.map(\.path)
        let primaryWorkspace = allWorkspacePaths.first ?? context.workspaceContext.workspacePath.path

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
                        let absPath = (filePath as NSString).isAbsolutePath ? filePath : (primaryWorkspace as NSString).appendingPathComponent(filePath)
                        files.append((path: absPath, line: lineNum, content: trimmed))
                    }
                }
            }
        }

        // Fallback to ripgrep across all workspace folders if no index results
        if files.isEmpty {
            let searchPaths = allWorkspacePaths.isEmpty ? ["."] : allWorkspacePaths
            let rgArgs = ["-rn", "--no-heading", query] + searchPaths
            let (output, _, _) = await shellExec(args: ["/usr/bin/rg"] + rgArgs, cwd: primaryWorkspace, timeout: 15_000)
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
        let searchPaths = context.workspaceContext.workspacePaths.map(\.path)
        let primaryWorkspace = searchPaths.first ?? context.workspaceContext.workspacePath.path

        guard !pattern.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "pattern is required"], durationMs: 0)
        }

        // Use ripgrep to find matching files across all workspace folders
        var rgArgs = ["-l", "--no-heading"]
        if !fileType.isEmpty { rgArgs += ["-t", fileType] }
        rgArgs.append(pattern)
        rgArgs.append(contentsOf: searchPaths.isEmpty ? ["."] : searchPaths)

        let (output, _, _) = await shellExec(args: ["/usr/bin/rg"] + rgArgs, cwd: primaryWorkspace, timeout: 15_000)
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
        // Batch mode: log multiple entries at once
        if let batchJSON = call.args["batch"], !batchJSON.isEmpty {
            return await executeDebugLogBatch(batchJSON: batchJSON, call: call, startDate: startDate)
        }

        let severity = call.args["severity"] ?? "info"
        let source = call.args["source"] ?? "agent"
        let message = call.args["message"] ?? ""
        let detail = call.args["detail"]
        let category = call.args["category"]
        let tags = call.args["tags"]
        let stackTrace = call.args["stack_trace"]
        let data = call.args["data"]
        let runId = call.args["run_id"] ?? call.args["runId"]
        let hypothesisId = call.args["hypothesis_id"] ?? call.args["hypothesisId"]

        guard !message.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "message is required"], durationMs: 0)
        }

        let enrichedDetail: String? = {
            var parts: [String] = []
            if let d = detail { parts.append(d) }
            if let st = stackTrace { parts.append("Stack Trace:\n\(st)") }
            if let t = tags { parts.append("Tags: \(t)") }
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }()

        if let category, category == "runtime" || category == "instrumentation" {
            await debugLogServer.logRuntime(
                source: source,
                message: message,
                severity: severity,
                detail: enrichedDetail,
                category: category,
                data: parseDebugDataArg(data),
                runId: runId,
                hypothesisId: hypothesisId
            )
        } else {
            await debugLogServer.log(severity: severity, source: source, message: message, detail: enrichedDetail, category: category)
        }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: true, payload: [
            "title": "debug_log",
            "detail": "[\(severity.uppercased())] \(message)",
            "output": "Logged: [\(severity)] \(source): \(message)\(tags != nil ? " [tags: \(tags!)]" : "")\(hypothesisId != nil ? " [hypothesis: \(hypothesisId!)]" : "")",
            "severity": severity,
            "source": source,
            "message": message,
            "log_detail": enrichedDetail ?? "",
            "category": category ?? "",
            "tags": tags ?? "",
            "stack_trace": stackTrace ?? "",
            "data": data ?? "",
            "run_id": runId ?? "",
            "hypothesis_id": hypothesisId ?? ""
        ], durationMs: ms)
    }

    private func executeDebugLogBatch(batchJSON: String, call: ToolCall, startDate: Date) async -> ToolResult {
        guard let jsonData = batchJSON.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]] else {
            return ToolResult(ok: false, payload: ["detail": "batch must be a JSON array of log entries: [{severity, source, message, ...}]"], durationMs: 0)
        }

        var logged = 0
        for entry in entries {
            let sev = entry["severity"] ?? "info"
            let src = entry["source"] ?? "agent"
            let msg = entry["message"] ?? ""
            let det = entry["detail"]
            let cat = entry["category"]
            guard !msg.isEmpty else { continue }

            await debugLogServer.log(severity: sev, source: src, message: msg, detail: det, category: cat)
            logged += 1
        }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: true, payload: [
            "title": "debug_log (batch)",
            "detail": "Batch logged \(logged) entries",
            "output": "Batch logged \(logged)/\(entries.count) entries",
            "logged_count": "\(logged)",
            "total_count": "\(entries.count)"
        ], durationMs: ms)
    }

    private func executeDebugQuery(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let severity = call.args["severity"]
        let category = call.args["category"]
        let source = call.args["source"]
        let search = call.args["search"] ?? call.args["query"]
        let tags = call.args["tags"]
        let hypothesisId = call.args["hypothesis_id"]
        let timeRange = call.args["time_range"]
        let groupBy = call.args["group_by"]
        let requestedLimit = Int(call.args["limit"] ?? "50") ?? 50
        let limit = min(max(requestedLimit, 1), 500)
        let format = (call.args["format"] ?? "summary").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if format == "summary",
           severity == nil, category == nil, source == nil, tags == nil, hypothesisId == nil,
           (search?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            let summary = await debugLogServer.sessionSummary()
            let ms = Int(Date().timeIntervalSince(startDate) * 1000)
            return ToolResult(ok: true, payload: [
                "title": "debug_query",
                "detail": "Debug session summary",
                "output": summary,
                "format": "summary"
            ], durationMs: ms)
        }

        var result = await debugLogServer.query(
            severity: severity,
            category: category,
            source: source,
            search: search,
            limit: limit
        )

        // Post-filter by tags
        if let tags, !tags.isEmpty {
            let tagSet = Set(tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
            result = result.filteredByDetail { detail in
                guard let d = detail?.lowercased() else { return false }
                return tagSet.contains(where: { d.contains($0) })
            }
        }

        // Post-filter by hypothesis_id
        if let hypothesisId, !hypothesisId.isEmpty {
            result = result.filteredByDetail { detail in
                detail?.contains(hypothesisId) ?? false
            }
        }

        // Post-filter by time_range (minutes)
        if let timeRange, let minutes = Double(timeRange), minutes > 0 {
            let cutoff = Date().addingTimeInterval(-minutes * 60)
            result = result.filteredByTime(after: cutoff)
        }

        // Group-by aggregation
        if let groupBy, !groupBy.isEmpty {
            let output = buildGroupByOutput(result: result, groupBy: groupBy)
            let ms = Int(Date().timeIntervalSince(startDate) * 1000)
            return ToolResult(ok: true, payload: [
                "title": "debug_query (grouped)",
                "detail": "Grouped by \(groupBy): \(result.totalCount) entries",
                "output": output,
                "format": "grouped",
                "group_by": groupBy
            ], durationMs: ms)
        }

        let output: String
        switch format {
        case "json":
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let jsonEntries = result.entries.map { entry -> [String: String] in
                var e: [String: String] = [
                    "timestamp": formatter.string(from: entry.timestamp),
                    "severity": entry.severity,
                    "source": entry.source,
                    "message": entry.message
                ]
                if let d = entry.detail { e["detail"] = d }
                if let c = entry.category { e["category"] = c }
                return e
            }
            if let jsonData = try? JSONSerialization.data(withJSONObject: jsonEntries, options: [.prettyPrinted, .sortedKeys]),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                output = jsonStr
            } else {
                output = "Failed to serialize to JSON"
            }
        case "markdown":
            var md = "# Debug Log Report\n\n"
            md += "| Time | Severity | Source | Message |\n|------|----------|--------|---------|\n"
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withTime, .withColonSeparatorInTime]
            for entry in result.entries {
                let ts = formatter.string(from: entry.timestamp)
                md += "| \(ts) | \(entry.severity.uppercased()) | \(entry.source) | \(entry.message) |\n"
            }
            md += "\n**Total**: \(result.totalCount), **Errors**: \(result.errorCount), **Warnings**: \(result.warningCount)"
            output = md
        case "summary":
            output = """
            Debug Query Summary:
              Total entries: \(result.totalCount)
              Errors: \(result.errorCount)
              Warnings: \(result.warningCount)
            """
        default:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withTime, .withColonSeparatorInTime]
            output = result.entries.isEmpty
                ? "No log entries matched the query."
                : result.entries.map { entry in
                    let ts = formatter.string(from: entry.timestamp)
                    let cat = entry.category.map { "[\($0)] " } ?? ""
                    let detail = entry.detail.map { "\n  detail: \($0)" } ?? ""
                    return "[\(ts)] \(entry.severity.uppercased()) \(cat)\(entry.source): \(entry.message)\(detail)"
                }.joined(separator: "\n")
        }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: true, payload: [
            "title": "debug_query",
            "detail": "\(result.totalCount) entries (\(result.errorCount) errors, \(result.warningCount) warnings)",
            "output": output,
            "format": format
        ], durationMs: ms)
    }

    private func buildGroupByOutput(result: DebugLogServer.QueryResult, groupBy: String) -> String {
        var groups: [String: Int] = [:]
        for entry in result.entries {
            let key: String
            switch groupBy.lowercased() {
            case "severity": key = entry.severity
            case "source": key = entry.source
            case "category": key = entry.category ?? "(none)"
            default: key = entry.severity
            }
            groups[key, default: 0] += 1
        }
        let sorted = groups.sorted { $0.value > $1.value }
        var lines = ["## Group by: \(groupBy) (\(result.totalCount) total)"]
        for (key, count) in sorted {
            let bar = String(repeating: "█", count: min(count, 40))
            lines.append("  \(key): \(count) \(bar)")
        }
        return lines.joined(separator: "\n")
    }

    private var debugSessionSnapshots: [String: [String: String]] = [:]
    private var debugSessionStartTime: Date?

    private func executeDebugSession(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let action = (call.args["action"] ?? "start").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let label = (call.args["label"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)

        switch action {
        case "start":
            let sessionId = await debugLogServer.startSession()
            debugHypotheses.removeAll()
            debugSessionSnapshots.removeAll()
            debugSessionStartTime = Date()
            return ToolResult(ok: true, payload: [
                "title": "debug_session",
                "detail": "Debug session started (id: \(sessionId.prefix(8)))",
                "output": "Session \(sessionId) started",
                "action": "start",
                "session_id": sessionId
            ], durationMs: ms)

        case "end", "stop":
            await debugLogServer.endSession()
            let summary = await debugLogServer.sessionSummary()
            debugSessionStartTime = nil
            return ToolResult(ok: true, payload: [
                "title": "debug_session",
                "detail": "Debug session ended",
                "output": summary,
                "action": action
            ], durationMs: ms)

        case "clear":
            await debugLogServer.clearSession()
            debugHypotheses.removeAll()
            debugSessionSnapshots.removeAll()
            return ToolResult(ok: true, payload: [
                "title": "debug_session",
                "detail": "Session logs cleared",
                "output": "Session logs cleared",
                "action": "clear"
            ], durationMs: ms)

        case "snapshot":
            let snapshotLabel = label.isEmpty ? "snapshot-\(debugSessionSnapshots.count + 1)" : label
            let logResult = await debugLogServer.query(limit: 500)
            let hypothesesSummary = debugHypotheses.map { (id, h) in
                "\(id.prefix(8)): [\(h.status)] \(h.title) (\(h.confidence)%)"
            }.joined(separator: "\n")

            let snapshot: [String: String] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "log_count": "\(logResult.totalCount)",
                "error_count": "\(logResult.errorCount)",
                "warning_count": "\(logResult.warningCount)",
                "hypothesis_count": "\(debugHypotheses.count)",
                "hypotheses": hypothesesSummary,
                "label": snapshotLabel
            ]
            debugSessionSnapshots[snapshotLabel] = snapshot

            return ToolResult(ok: true, payload: [
                "title": "debug_session",
                "detail": "Snapshot '\(snapshotLabel)' saved",
                "output": "Snapshot '\(snapshotLabel)': \(logResult.totalCount) logs, \(logResult.errorCount) errors, \(debugHypotheses.count) hypotheses",
                "action": "snapshot",
                "label": snapshotLabel,
                "snapshot_count": "\(debugSessionSnapshots.count)"
            ], durationMs: ms)

        case "export":
            let logResult = await debugLogServer.query(limit: 200)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withTime, .withColonSeparatorInTime]

            var md = "# Debug Session Report\n\n"
            if let start = debugSessionStartTime {
                let duration = Int(Date().timeIntervalSince(start))
                md += "**Duration**: \(duration / 60)m \(duration % 60)s\n\n"
            }

            md += "## Hypotheses (\(debugHypotheses.count))\n\n"
            for (id, h) in debugHypotheses.sorted(by: { $0.value.confidence > $1.value.confidence }) {
                md += "### \(h.title)\n"
                md += "- ID: `\(id.prefix(8))`\n"
                md += "- Status: **\(h.status)** | Confidence: \(h.confidence)%\n"
                if !h.rootCauseType.isEmpty { md += "- Type: \(h.rootCauseType)\n" }
                if !h.relatedFiles.isEmpty { md += "- Files: \(h.relatedFiles.joined(separator: ", "))\n" }
                if !h.description.isEmpty { md += "- \(h.description)\n" }
                md += "\n"
            }

            md += "## Log Summary\n\n"
            md += "- Total: \(logResult.totalCount)\n"
            md += "- Errors: \(logResult.errorCount)\n"
            md += "- Warnings: \(logResult.warningCount)\n\n"

            if !logResult.entries.isEmpty {
                md += "## Recent Logs\n\n"
                for entry in logResult.entries.suffix(50) {
                    let ts = formatter.string(from: entry.timestamp)
                    md += "- `[\(ts)]` **\(entry.severity.uppercased())** \(entry.source): \(entry.message)\n"
                }
            }

            return ToolResult(ok: true, payload: [
                "title": "debug_session",
                "detail": "Session exported as markdown",
                "output": md,
                "action": "export"
            ], durationMs: ms)

        case "stats":
            let logResult = await debugLogServer.query(limit: 1)
            var stats = "## Session Statistics\n\n"
            if let start = debugSessionStartTime {
                let duration = Int(Date().timeIntervalSince(start))
                stats += "Duration: \(duration / 60)m \(duration % 60)s\n"
            }
            stats += "Total logs: \(logResult.totalCount)\n"
            stats += "Errors: \(logResult.errorCount)\n"
            stats += "Warnings: \(logResult.warningCount)\n"
            stats += "Hypotheses: \(debugHypotheses.count)\n"

            let statusCounts = Dictionary(grouping: debugHypotheses.values, by: \.status).mapValues(\.count)
            for (status, count) in statusCounts.sorted(by: { $0.key < $1.key }) {
                stats += "  - \(status): \(count)\n"
            }
            stats += "Snapshots: \(debugSessionSnapshots.count)\n"

            return ToolResult(ok: true, payload: [
                "title": "debug_session",
                "detail": "Session stats: \(logResult.totalCount) logs, \(debugHypotheses.count) hypotheses",
                "output": stats,
                "action": "stats"
            ], durationMs: ms)

        default:
            return ToolResult(ok: false, payload: ["detail": "Unknown action: \(action). Use start, end, clear, snapshot, export, or stats."], durationMs: ms)
        }
    }

    private func executeDebugHypothesize(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let title = (call.args["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (call.args["description"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let action = (call.args["action"] ?? "propose").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hypothesisId = (call.args["hypothesis_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedStatus = (call.args["status"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let evidence = call.args["evidence"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let confidence = Int(call.args["confidence"] ?? "") ?? -1
        let rootCauseType = (call.args["root_cause_type"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let relatedFiles = (call.args["related_files"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let relatedTests = (call.args["related_tests"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)

        switch action {
        case "propose":
            guard !title.isEmpty else {
                return ToolResult(ok: false, payload: ["detail": "title is required for propose action"], durationMs: ms)
            }

            let newHypothesisId = UUID().uuidString
            let normalizedStatus = normalizeHypothesisStatus(requestedStatus, fallback: "proposed")
            let clampedConfidence = confidence >= 0 ? min(max(confidence, 0), 100) : 50

            debugHypotheses[newHypothesisId] = DebugHypothesis(
                title: title,
                description: description,
                status: normalizedStatus,
                confidence: clampedConfidence,
                rootCauseType: rootCauseType,
                relatedFiles: relatedFiles,
                relatedTests: relatedTests,
                evidence: evidence != nil ? [evidence!] : [],
                createdAt: Date()
            )

            var logDetail = description
            if !rootCauseType.isEmpty { logDetail += "\nType: \(rootCauseType)" }
            if !relatedFiles.isEmpty { logDetail += "\nFiles: \(relatedFiles.joined(separator: ", "))" }

            await debugLogServer.log(
                severity: "info",
                source: "hypothesis",
                message: "Hypothesis \(newHypothesisId.prefix(8)) proposed: \(title) [confidence: \(clampedConfidence)%]",
                detail: logDetail,
                category: "debug"
            )

            var output = "Proposed hypothesis \(newHypothesisId.prefix(8)): \(title)\n"
            output += "  Status: \(normalizedStatus)\n"
            output += "  Confidence: \(clampedConfidence)%\n"
            if !rootCauseType.isEmpty { output += "  Root cause type: \(rootCauseType)\n" }
            if !relatedFiles.isEmpty { output += "  Related files: \(relatedFiles.joined(separator: ", "))\n" }
            if !relatedTests.isEmpty { output += "  Related tests: \(relatedTests.joined(separator: ", "))\n" }

            return ToolResult(ok: true, payload: [
                "title": "debug_hypothesize",
                "detail": "Hypothesis proposed: \(title) [\(clampedConfidence)%]",
                "output": output,
                "action": "propose",
                "hypothesis_id": newHypothesisId,
                "hypothesis_title": title,
                "description": description,
                "hypothesis_status": normalizedStatus,
                "confidence": "\(clampedConfidence)",
                "root_cause_type": rootCauseType,
                "related_files": relatedFiles.joined(separator: ","),
                "evidence": evidence ?? ""
            ], durationMs: ms)

        case "update":
            guard !hypothesisId.isEmpty else {
                return ToolResult(ok: false, payload: ["detail": "hypothesis_id is required for update"], durationMs: ms)
            }
            guard var existing = debugHypotheses[hypothesisId] else {
                return ToolResult(ok: false, payload: ["detail": "Unknown hypothesis_id: \(hypothesisId)"], durationMs: ms)
            }

            let nextStatus = normalizeHypothesisStatus(requestedStatus, fallback: existing.status)
            existing.status = nextStatus
            if confidence >= 0 { existing.confidence = min(max(confidence, 0), 100) }
            if !rootCauseType.isEmpty { existing.rootCauseType = rootCauseType }
            if !relatedFiles.isEmpty { existing.relatedFiles = relatedFiles }
            if !relatedTests.isEmpty { existing.relatedTests = relatedTests }
            if let evidence { existing.evidence.append(evidence) }
            debugHypotheses[hypothesisId] = existing

            await debugLogServer.log(
                severity: "info",
                source: "hypothesis",
                message: "Hypothesis \(hypothesisId.prefix(8)) updated to \(nextStatus) [confidence: \(existing.confidence)%]",
                detail: evidence,
                category: "debug"
            )

            var output = "Updated hypothesis \(hypothesisId.prefix(8)) -> \(nextStatus)\n"
            output += "  Title: \(existing.title)\n"
            output += "  Confidence: \(existing.confidence)%\n"
            if !existing.rootCauseType.isEmpty { output += "  Root cause type: \(existing.rootCauseType)\n" }
            if !existing.relatedFiles.isEmpty { output += "  Related files: \(existing.relatedFiles.joined(separator: ", "))\n" }
            if existing.evidence.count > 1 { output += "  Evidence entries: \(existing.evidence.count)\n" }

            return ToolResult(ok: true, payload: [
                "title": "debug_hypothesize",
                "detail": "Hypothesis updated to \(nextStatus) [\(existing.confidence)%]",
                "output": output,
                "action": "update",
                "hypothesis_id": hypothesisId,
                "hypothesis_title": existing.title,
                "description": existing.description,
                "hypothesis_status": nextStatus,
                "confidence": "\(existing.confidence)",
                "root_cause_type": existing.rootCauseType,
                "related_files": existing.relatedFiles.joined(separator: ","),
                "evidence": evidence ?? ""
            ], durationMs: ms)

        default:
            return ToolResult(ok: false, payload: ["detail": "Unknown action: \(action). Use propose or update."], durationMs: ms)
        }
    }

    // MARK: - debug_mark: Insert a typed debug marker/instrumentation into a file

    private func executeDebugMark(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let rawPath = call.args["path"] ?? ""
        let lineStr = call.args["line"] ?? ""
        let comment = call.args["comment"] ?? "DEBUG"
        let code = call.args["code"] ?? ""
        let markerType = (call.args["type"] ?? "marker").lowercased()
        let expression = call.args["expression"] ?? ""
        let hypothesisId = call.args["hypothesis_id"] ?? ""
        let workspace = context.workspaceContext.workspacePath.path

        guard !rawPath.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "path is required"], durationMs: 0)
        }
        guard let lineNum = Int(lineStr), lineNum > 0 else {
            return ToolResult(ok: false, payload: ["detail": "valid line number is required"], durationMs: 0)
        }

        let path = (rawPath as NSString).isAbsolutePath ? rawPath : (workspace as NSString).appendingPathComponent(rawPath)
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        let hypTag = hypothesisId.isEmpty ? "" : " [H:\(hypothesisId.prefix(8))]"

        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            var lines = content.components(separatedBy: "\n")
            let insertIdx = min(lineNum, lines.count)

            let markerLine: String
            if !code.isEmpty {
                markerLine = code + " // \u{1F41B} DEBUG[\(markerType)]: \(comment)\(hypTag)"
            } else {
                switch markerType {
                case "log":
                    let expr = expression.isEmpty ? "\"checkpoint\"" : expression
                    markerLine = "print(\"\\u{1F41B} DEBUG[\\(#file):\\(#line)] \(comment): \\(\(expr))\") // \u{1F41B} DEBUG[log]: \(comment)\(hypTag)"
                case "assert":
                    let expr = expression.isEmpty ? "true" : expression
                    markerLine = "assert(\(expr), \"\\u{1F41B} DEBUG ASSERT: \(comment)\") // \u{1F41B} DEBUG[assert]: \(comment)\(hypTag)"
                case "timing":
                    markerLine = "let _debugTimerStart_\(lineNum) = CFAbsoluteTimeGetCurrent(); defer { print(\"\\u{1F41B} DEBUG TIMING [\(comment)]: \\(CFAbsoluteTimeGetCurrent() - _debugTimerStart_\(lineNum))s\") } // \u{1F41B} DEBUG[timing]: \(comment)\(hypTag)"
                case "variable":
                    let expr = expression.isEmpty ? "self" : expression
                    markerLine = "print(\"\\u{1F41B} DEBUG VAR [\(comment)] \(expr) = \\(\(expr))\") // \u{1F41B} DEBUG[variable]: \(comment)\(hypTag)"
                default:
                    markerLine = "// \u{1F41B} DEBUG[marker]: \(comment)\(hypTag)"
                }
            }

            lines.insert(markerLine, at: insertIdx)
            try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: String.Encoding.utf8)

            await debugLogServer.log(
                severity: "info",
                source: "debug_mark",
                message: "[\(markerType)] Marker inserted at \((path as NSString).lastPathComponent):\(lineNum)",
                detail: markerLine,
                category: "debug"
            )

            return ToolResult(ok: true, payload: [
                "title": "debug_mark",
                "detail": "[\(markerType)] marker at \((path as NSString).lastPathComponent):\(lineNum)",
                "output": "Inserted [\(markerType)]: \(markerLine)",
                "marker_info": "\(path)|\(lineNum)|\(comment)|\(markerType)",
                "path": path,
                "line": "\(lineNum)",
                "comment": comment,
                "type": markerType,
                "hypothesis_id": hypothesisId
            ], durationMs: ms)
        } catch {
            return ToolResult(ok: false, payload: [
                "title": "debug_mark",
                "detail": "Failed to insert marker: \(error.localizedDescription)"
            ], durationMs: ms)
        }
    }

    // MARK: - debug_clean: Remove debug markers with type filtering, dry-run, and hypothesis scoping

    private func executeDebugClean(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let rawPath = call.args["path"] ?? ""
        let cleanType = (call.args["type"] ?? "all").lowercased()
        let isDryRun = call.args["dry_run"]?.lowercased() == "true"
        let hypothesisId = call.args["hypothesis_id"] ?? ""
        let workspace = context.workspaceContext.workspacePath.path
        let debugTag = "\u{1F41B} DEBUG"
        var cleanedCount = 0
        var previewLines: [String] = []
        var errors: [String] = []

        let filesToClean: [String]
        if !rawPath.isEmpty {
            let path = (rawPath as NSString).isAbsolutePath ? rawPath : (workspace as NSString).appendingPathComponent(rawPath)
            filesToClean = [path]
        } else {
            let (output, _, _) = await shellExec(args: ["/usr/bin/rg", "-l", "--no-heading", debugTag, workspace], cwd: workspace, timeout: 15_000)
            filesToClean = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        }

        let typePatterns: [String]
        switch cleanType {
        case "markers": typePatterns = ["DEBUG[marker]"]
        case "logs": typePatterns = ["DEBUG[log]"]
        case "asserts": typePatterns = ["DEBUG[assert]"]
        case "timing": typePatterns = ["DEBUG[timing]"]
        case "variables": typePatterns = ["DEBUG[variable]"]
        default: typePatterns = [debugTag]
        }

        for filePath in filesToClean {
            do {
                let content = try String(contentsOfFile: filePath, encoding: .utf8)
                let lines = content.components(separatedBy: "\n")
                let fileName = (filePath as NSString).lastPathComponent

                let filtered = lines.enumerated().compactMap { (idx, line) -> String? in
                    let shouldRemove = typePatterns.contains(where: { line.contains($0) })
                    let matchesHypothesis = hypothesisId.isEmpty || line.contains("[H:\(hypothesisId.prefix(8))]")

                    if shouldRemove && matchesHypothesis {
                        cleanedCount += 1
                        if isDryRun {
                            previewLines.append("  \(fileName):\(idx + 1) | \(line.trimmingCharacters(in: .whitespaces))")
                        }
                        return nil
                    }
                    return line
                }

                if !isDryRun && filtered.count < lines.count {
                    try filtered.joined(separator: "\n").write(toFile: filePath, atomically: true, encoding: String.Encoding.utf8)
                }
            } catch {
                errors.append("\((filePath as NSString).lastPathComponent): \(error.localizedDescription)")
            }
        }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        let modeLabel = isDryRun ? "DRY RUN" : "CLEANED"
        let typeLabel = cleanType == "all" ? "all types" : cleanType
        let detail: String
        let isSuccess: Bool

        if !errors.isEmpty {
            detail = "[\(modeLabel)] \(cleanedCount) markers (\(typeLabel)) in \(filesToClean.count) files; errors: \(errors.prefix(3).joined(separator: "; "))"
            isSuccess = false
        } else if cleanedCount == 0 {
            detail = "No \(typeLabel) debug markers found"
            isSuccess = true
        } else {
            detail = "[\(modeLabel)] \(cleanedCount) \(typeLabel) markers in \(filesToClean.count) files"
            isSuccess = true
        }

        var output = detail
        if isDryRun && !previewLines.isEmpty {
            output += "\n\nWould remove:\n" + previewLines.prefix(30).joined(separator: "\n")
            if previewLines.count > 30 { output += "\n  ... +\(previewLines.count - 30) more" }
        }

        await debugLogServer.log(severity: "info", source: "debug_clean", message: detail, category: "debug")

        return ToolResult(ok: isSuccess, payload: [
            "title": "debug_clean",
            "detail": detail,
            "output": output,
            "cleaned_markers": "\(cleanedCount)",
            "cleaned_files": "\(filesToClean.count)",
            "type": cleanType,
            "dry_run": isDryRun ? "true" : "false",
            "status": isSuccess ? "completed" : "failed"
        ], durationMs: ms)
    }

    // MARK: - debug_trace_analyze: Parse and analyze errors, stack traces, crash logs

    private func executeDebugTraceAnalyze(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let errorText = call.args["error_text"] ?? ""
        let errorTypeHint = (call.args["error_type"] ?? "").lowercased()
        let extraContext = call.args["context"] ?? ""
        let workspace = context.workspaceContext.workspacePath.path

        guard !errorText.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "error_text is required"], durationMs: 0)
        }

        var analysis: [String] = []
        var extractedFiles: [(file: String, line: Int, col: Int?)] = []
        var suggestedCauses: [String] = []

        // Auto-detect error type
        let detectedType: String
        if !errorTypeHint.isEmpty {
            detectedType = errorTypeHint
        } else if errorText.contains("error:") && (errorText.contains(".swift:") || errorText.contains(".m:")) {
            detectedType = "compile"
        } else if errorText.contains("Fatal error") || errorText.contains("Thread ") || errorText.contains("EXC_") {
            detectedType = "crash"
        } else if errorText.contains("XCTAssert") || errorText.contains("failed -") || errorText.contains("FAIL") {
            detectedType = "test_failure"
        } else if errorText.contains("Assertion failed") || errorText.contains("precondition") {
            detectedType = "assertion"
        } else {
            detectedType = "runtime"
        }
        analysis.append("## Error Type: \(detectedType)")

        let lines = errorText.components(separatedBy: "\n")

        // Parse Swift compiler errors: file.swift:line:col: error: message
        let compilerPattern = try? NSRegularExpression(pattern: #"([^\s:]+\.\w+):(\d+):(\d+):\s*(error|warning|note):\s*(.+)"#)
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = compilerPattern?.firstMatch(in: line, range: range) {
                let file = String(line[Range(match.range(at: 1), in: line)!])
                let lineNum = Int(line[Range(match.range(at: 2), in: line)!]) ?? 0
                let col = Int(line[Range(match.range(at: 3), in: line)!])
                let severity = String(line[Range(match.range(at: 4), in: line)!])
                let message = String(line[Range(match.range(at: 5), in: line)!])

                if severity == "error" || severity == "warning" {
                    extractedFiles.append((file: file, line: lineNum, col: col))
                    suggestedCauses.append("\(severity): \(message) at \(file):\(lineNum)")
                }
            }
        }

        // Parse stack trace frames: N ModuleName 0xADDR functionName + offset
        let stackPattern = try? NSRegularExpression(pattern: #"^\d+\s+(\S+)\s+0x[0-9a-fA-F]+\s+(.+)\s*\+\s*\d+"#, options: .anchorsMatchLines)
        var stackFrames: [String] = []
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = stackPattern?.firstMatch(in: line, range: range) {
                let module = String(line[Range(match.range(at: 1), in: line)!])
                let symbol = String(line[Range(match.range(at: 2), in: line)!])
                stackFrames.append("\(module): \(symbol)")
            }
        }
        if !stackFrames.isEmpty {
            analysis.append("## Stack Trace (\(stackFrames.count) frames)\n" + stackFrames.prefix(15).enumerated().map { "  #\($0.offset) \($0.element)" }.joined(separator: "\n"))
        }

        // Parse test assertion failures: XCTAssertEqual failed: ("A") is not equal to ("B")
        let assertPattern = try? NSRegularExpression(pattern: #"(XCT\w+)\s+failed[:\s]*(.+)"#)
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = assertPattern?.firstMatch(in: line, range: range) {
                let assertType = String(line[Range(match.range(at: 1), in: line)!])
                let detail = String(line[Range(match.range(at: 2), in: line)!])
                suggestedCauses.append("Test \(assertType) failed: \(detail)")
            }
        }

        // Check if extracted files exist in workspace
        var existingFiles: [String] = []
        var missingFiles: [String] = []
        for extracted in extractedFiles {
            let fullPath = extracted.file.hasPrefix("/") ? extracted.file : workspace + "/" + extracted.file
            if FileManager.default.fileExists(atPath: fullPath) {
                existingFiles.append("\(extracted.file):\(extracted.line)")
            } else {
                missingFiles.append(extracted.file)
            }
        }

        if !extractedFiles.isEmpty {
            analysis.append("## Files Involved (\(extractedFiles.count))\n" + extractedFiles.map { "  - \($0.file):\($0.line)\($0.col != nil ? ":\($0.col!)" : "")" }.joined(separator: "\n"))
        }

        if !suggestedCauses.isEmpty {
            analysis.append("## Suggested Causes (\(suggestedCauses.count))\n" + suggestedCauses.enumerated().map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        }

        if !existingFiles.isEmpty {
            analysis.append("## Files to Investigate\n" + existingFiles.map { "  - \($0)" }.joined(separator: "\n"))
        }

        if !extraContext.isEmpty {
            analysis.append("## Additional Context\n\(extraContext)")
        }

        await debugLogServer.log(
            severity: "info",
            source: "debug_trace_analyze",
            message: "Analyzed \(detectedType) error: \(extractedFiles.count) files, \(suggestedCauses.count) causes",
            detail: analysis.joined(separator: "\n\n"),
            category: "debug"
        )

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: true, payload: [
            "title": "debug_trace_analyze",
            "detail": "\(detectedType): \(extractedFiles.count) files, \(suggestedCauses.count) causes, \(stackFrames.count) stack frames",
            "output": analysis.joined(separator: "\n\n"),
            "error_type": detectedType,
            "files_count": "\(extractedFiles.count)",
            "causes_count": "\(suggestedCauses.count)",
            "stack_frames": "\(stackFrames.count)"
        ], durationMs: ms)
    }

    // MARK: - debug_instrument: Insert intelligent executable instrumentation

    private func executeDebugInstrument(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let rawPath = call.args["path"] ?? ""
        let lineStr = call.args["line"] ?? ""
        let instrType = (call.args["type"] ?? "log").lowercased()
        let expression = call.args["expression"] ?? ""
        let condition = call.args["condition"] ?? ""
        let hypothesisId = call.args["hypothesis_id"] ?? ""
        let label = call.args["label"] ?? ""
        let workspace = context.workspaceContext.workspacePath.path

        guard !rawPath.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "path is required"], durationMs: 0)
        }
        guard let lineNum = Int(lineStr), lineNum > 0 else {
            return ToolResult(ok: false, payload: ["detail": "valid line number is required"], durationMs: 0)
        }
        guard !expression.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "expression is required"], durationMs: 0)
        }

        let path = (rawPath as NSString).isAbsolutePath ? rawPath : (workspace as NSString).appendingPathComponent(rawPath)
        let hypTag = hypothesisId.isEmpty ? "" : " [H:\(hypothesisId.prefix(8))]"
        let labelTag = label.isEmpty ? "" : " [\(label)]"

        let generatedCode: String
        switch instrType {
        case "log":
            generatedCode = "print(\"\\u{1F50D} INSTRUMENT\(labelTag): \\(\(expression))\") // \u{1F41B} DEBUG[instrument-log]: \(label.isEmpty ? expression : label)\(hypTag)"
        case "assert":
            let msg = condition.isEmpty ? expression : condition
            generatedCode = "assert(\(expression), \"\\u{1F6A8} INSTRUMENT ASSERT\(labelTag): \(msg)\") // \u{1F41B} DEBUG[instrument-assert]: \(label.isEmpty ? expression : label)\(hypTag)"
        case "timing":
            let timerName = "_instrTimer_\(lineNum)"
            generatedCode = "let \(timerName) = CFAbsoluteTimeGetCurrent(); defer { print(\"\\u{23F1} INSTRUMENT TIMING\(labelTag): \\(String(format: \"%.4f\", CFAbsoluteTimeGetCurrent() - \(timerName)))s for \(expression)\") } // \u{1F41B} DEBUG[instrument-timing]: \(label.isEmpty ? expression : label)\(hypTag)"
        case "variable":
            generatedCode = "print(\"\\u{1F4CB} INSTRUMENT VAR\(labelTag) \(expression) = \\(\(expression)) [type: \\(type(of: \(expression)))]\") // \u{1F41B} DEBUG[instrument-variable]: \(label.isEmpty ? expression : label)\(hypTag)"
        case "conditional_break":
            let cond = condition.isEmpty ? "true" : condition
            generatedCode = "if \(cond) { print(\"\\u{1F6D1} INSTRUMENT BREAK\(labelTag): condition met — \(expression) = \\(\(expression))\") } // \u{1F41B} DEBUG[instrument-conditional]: \(label.isEmpty ? expression : label)\(hypTag)"
        default:
            generatedCode = "print(\"\\u{1F50D} INSTRUMENT\(labelTag): \\(\(expression))\") // \u{1F41B} DEBUG[instrument-log]: \(label.isEmpty ? expression : label)\(hypTag)"
        }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)

        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            var lines = content.components(separatedBy: "\n")
            let insertIdx = min(lineNum, lines.count)

            lines.insert(generatedCode, at: insertIdx)
            try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: String.Encoding.utf8)

            await debugLogServer.log(
                severity: "info",
                source: "debug_instrument",
                message: "[\(instrType)] Instrumented \((path as NSString).lastPathComponent):\(lineNum)\(labelTag)",
                detail: generatedCode,
                category: "instrumentation"
            )

            return ToolResult(ok: true, payload: [
                "title": "debug_instrument",
                "detail": "[\(instrType)] instrumented \((path as NSString).lastPathComponent):\(lineNum)",
                "output": "Inserted [\(instrType)] instrumentation at line \(lineNum):\n\(generatedCode)",
                "path": path,
                "line": "\(lineNum)",
                "type": instrType,
                "expression": expression,
                "hypothesis_id": hypothesisId,
                "label": label
            ], durationMs: ms)
        } catch {
            return ToolResult(ok: false, payload: [
                "title": "debug_instrument",
                "detail": "Failed to instrument: \(error.localizedDescription)"
            ], durationMs: ms)
        }
    }

    // MARK: - debug_timeline: Chronological event timeline

    private func executeDebugTimeline(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let filterRaw = (call.args["filter"] ?? "all").lowercased()
        let filters = Set(filterRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let showAll = filters.contains("all")
        let timeRange = call.args["time_range"]
        let hypothesisId = call.args["hypothesis_id"]
        let format = (call.args["format"] ?? "text").lowercased()

        let allEntries = await debugLogServer.allEntries()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withTime, .withColonSeparatorInTime]

        var events: [(date: Date, type: String, text: String)] = []

        // Collect log events
        if showAll || filters.contains("logs") {
            for entry in allEntries {
                if let hid = hypothesisId, !(entry.hypothesisId == hid || (entry.detail?.contains(hid) ?? false)) {
                    continue
                }
                let cat = entry.category ?? "log"
                events.append((date: entry.timestamp, type: "log[\(cat)]", text: "[\(entry.severity.uppercased())] \(entry.source): \(entry.message)"))
            }
        }

        // Collect phase changes
        if showAll || filters.contains("phases") {
            for entry in allEntries where entry.category == "system" {
                events.append((date: entry.timestamp, type: "phase", text: entry.message))
            }
        }

        // Collect hypotheses events
        if showAll || filters.contains("hypotheses") {
            for entry in allEntries where entry.category == "debug" && entry.source == "hypothesis" {
                if let hid = hypothesisId, !entry.message.contains(hid.prefix(8)) { continue }
                events.append((date: entry.timestamp, type: "hypothesis", text: entry.message))
            }
        }

        // Collect marker events
        if showAll || filters.contains("markers") {
            for entry in allEntries where entry.source == "debug_mark" || entry.source == "debug_instrument" {
                events.append((date: entry.timestamp, type: "marker", text: entry.message))
            }
        }

        // Filter by time range
        if let timeRange, let minutes = Double(timeRange), minutes > 0 {
            let cutoff = Date().addingTimeInterval(-minutes * 60)
            events = events.filter { $0.date > cutoff }
        }

        events.sort { $0.date < $1.date }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)

        if events.isEmpty {
            return ToolResult(ok: true, payload: [
                "title": "debug_timeline",
                "detail": "No events found",
                "output": "No debug events match the filter criteria.",
                "event_count": "0"
            ], durationMs: ms)
        }

        let output: String
        if format == "mermaid" {
            var mermaid = "gantt\n    title Debug Timeline\n    dateFormat HH:mm:ss\n"
            for (i, event) in events.prefix(30).enumerated() {
                let ts = formatter.string(from: event.date)
                let safeText = event.text.prefix(40).replacingOccurrences(of: ":", with: "-")
                mermaid += "    \(event.type) \(i + 1) - \(safeText) : \(ts), 1s\n"
            }
            output = mermaid
        } else {
            var lines: [String] = ["## Debug Timeline (\(events.count) events)\n"]
            for event in events {
                let ts = formatter.string(from: event.date)
                let icon: String
                switch event.type {
                case "phase": icon = "🔄"
                case "hypothesis": icon = "💡"
                case "marker": icon = "📌"
                default: icon = "📝"
                }
                lines.append("  \(ts) \(icon) [\(event.type)] \(event.text)")
            }
            output = lines.joined(separator: "\n")
        }

        return ToolResult(ok: true, payload: [
            "title": "debug_timeline",
            "detail": "\(events.count) events (\(filterRaw))",
            "output": output,
            "event_count": "\(events.count)",
            "format": format
        ], durationMs: ms)
    }

    // MARK: - debug_snapshot: Capture and compare session state

    private func executeDebugSnapshot(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let action = (call.args["action"] ?? "capture").lowercased()
        let label = (call.args["label"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let compareWith = (call.args["compare_with"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)

        switch action {
        case "capture":
            let snapshotLabel = label.isEmpty ? "snap-\(debugSessionSnapshots.count + 1)" : label
            let logResult = await debugLogServer.query(limit: 500)

            let hypothesesData = debugHypotheses.map { (id, h) in
                "\(id.prefix(8))|[\(h.status)]\(h.title)|\(h.confidence)%"
            }.joined(separator: "\n")

            let snapshot: [String: String] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "log_count": "\(logResult.totalCount)",
                "error_count": "\(logResult.errorCount)",
                "warning_count": "\(logResult.warningCount)",
                "hypothesis_count": "\(debugHypotheses.count)",
                "hypotheses": hypothesesData,
                "confirmed_count": "\(debugHypotheses.values.filter { $0.status == "confirmed" }.count)",
                "rejected_count": "\(debugHypotheses.values.filter { $0.status == "rejected" }.count)",
                "label": snapshotLabel
            ]
            debugSessionSnapshots[snapshotLabel] = snapshot

            var output = "## Snapshot '\(snapshotLabel)' captured\n\n"
            output += "- Logs: \(logResult.totalCount) (\(logResult.errorCount) errors, \(logResult.warningCount) warnings)\n"
            output += "- Hypotheses: \(debugHypotheses.count)\n"
            for (id, h) in debugHypotheses {
                output += "  - \(id.prefix(8)): [\(h.status)] \(h.title) (\(h.confidence)%)\n"
            }

            return ToolResult(ok: true, payload: [
                "title": "debug_snapshot",
                "detail": "Snapshot '\(snapshotLabel)' captured",
                "output": output,
                "action": "capture",
                "label": snapshotLabel,
                "snapshot_count": "\(debugSessionSnapshots.count)"
            ], durationMs: ms)

        case "compare":
            guard !label.isEmpty else {
                return ToolResult(ok: false, payload: ["detail": "label is required for compare (current snapshot label)"], durationMs: ms)
            }
            guard !compareWith.isEmpty else {
                return ToolResult(ok: false, payload: ["detail": "compare_with is required (previous snapshot label)"], durationMs: ms)
            }
            guard let snapA = debugSessionSnapshots[compareWith] else {
                return ToolResult(ok: false, payload: ["detail": "Snapshot '\(compareWith)' not found. Available: \(debugSessionSnapshots.keys.sorted().joined(separator: ", "))"], durationMs: ms)
            }

            // Capture current state as snapB
            let logResult = await debugLogServer.query(limit: 1)
            let snapB: [String: String] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "log_count": "\(logResult.totalCount)",
                "error_count": "\(logResult.errorCount)",
                "warning_count": "\(logResult.warningCount)",
                "hypothesis_count": "\(debugHypotheses.count)",
                "confirmed_count": "\(debugHypotheses.values.filter { $0.status == "confirmed" }.count)",
                "rejected_count": "\(debugHypotheses.values.filter { $0.status == "rejected" }.count)",
                "label": label
            ]

            var diff = "## Snapshot Comparison: '\(compareWith)' -> '\(label)'\n\n"
            let fields = ["log_count", "error_count", "warning_count", "hypothesis_count", "confirmed_count", "rejected_count"]
            for field in fields {
                let a = Int(snapA[field] ?? "0") ?? 0
                let b = Int(snapB[field] ?? "0") ?? 0
                let delta = b - a
                let arrow = delta > 0 ? "↑\(delta)" : (delta < 0 ? "↓\(abs(delta))" : "→")
                diff += "- \(field): \(a) \(arrow) \(b)\n"
            }
            diff += "\n- Time: \(snapA["timestamp"] ?? "?") -> \(snapB["timestamp"] ?? "?")\n"

            return ToolResult(ok: true, payload: [
                "title": "debug_snapshot",
                "detail": "Compared '\(compareWith)' with current state",
                "output": diff,
                "action": "compare"
            ], durationMs: ms)

        case "list":
            if debugSessionSnapshots.isEmpty {
                return ToolResult(ok: true, payload: [
                    "title": "debug_snapshot",
                    "detail": "No snapshots available",
                    "output": "No snapshots have been captured yet. Use action=capture to save one.",
                    "action": "list"
                ], durationMs: ms)
            }

            var output = "## Available Snapshots (\(debugSessionSnapshots.count))\n\n"
            for (snapLabel, data) in debugSessionSnapshots.sorted(by: { ($0.value["timestamp"] ?? "") < ($1.value["timestamp"] ?? "") }) {
                output += "- **\(snapLabel)** (\(data["timestamp"] ?? "?")): \(data["log_count"] ?? "0") logs, \(data["hypothesis_count"] ?? "0") hypotheses\n"
            }

            return ToolResult(ok: true, payload: [
                "title": "debug_snapshot",
                "detail": "\(debugSessionSnapshots.count) snapshots available",
                "output": output,
                "action": "list"
            ], durationMs: ms)

        default:
            return ToolResult(ok: false, payload: ["detail": "Unknown action: \(action). Use capture, compare, or list."], durationMs: ms)
        }
    }

    // MARK: - debug_test_check: Targeted test verification

    private func executeDebugTestCheck(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let scope = (call.args["scope"] ?? "related").lowercased()
        let rawPath = call.args["path"] ?? ""
        let filter = call.args["filter"] ?? ""
        let hypothesisId = call.args["hypothesis_id"] ?? ""
        let timeoutMs = Int(call.args["timeout_ms"] ?? "60000") ?? 60000
        let workspace = context.workspaceContext.workspacePath.path

        var testArgs: [String] = ["/usr/bin/swift", "test"]

        // Determine test filter based on scope
        var testFilter = filter
        if testFilter.isEmpty {
            switch scope {
            case "file":
                if !rawPath.isEmpty {
                    let fileName = (rawPath as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
                    testFilter = fileName
                }
            case "related":
                if !rawPath.isEmpty {
                    let fileName = (rawPath as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
                    testFilter = fileName
                } else if !hypothesisId.isEmpty, let hyp = debugHypotheses[hypothesisId] {
                    let fileNames = hyp.relatedFiles.compactMap { ($0 as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "") }
                    if let first = fileNames.first { testFilter = first }
                }
            case "all":
                break
            default:
                break
            }
        }

        if !testFilter.isEmpty {
            testArgs += ["--filter", testFilter]
        }

        await debugLogServer.log(
            severity: "info",
            source: "debug_test_check",
            message: "Running tests [scope=\(scope)]\(testFilter.isEmpty ? "" : " filter=\(testFilter)")",
            category: "test"
        )

        let (stdout, stderr, exitCode) = await shellExec(
            args: testArgs,
            cwd: workspace,
            timeout: timeoutMs
        )

        let combined = (stdout + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse test results
        var passed = 0
        var failed = 0
        var failedTests: [String] = []
        let resultLines = combined.components(separatedBy: "\n")
        for line in resultLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("passed") && trimmed.contains("Test Case") {
                passed += 1
            } else if trimmed.contains("failed") && trimmed.contains("Test Case") {
                failed += 1
                failedTests.append(trimmed)
            }
        }

        // Check for overall pass/fail from Swift test summary
        let overallPassed = exitCode == 0

        await debugLogServer.log(
            severity: overallPassed ? "info" : "error",
            source: "debug_test_check",
            message: "Tests \(overallPassed ? "PASSED" : "FAILED"): \(passed) passed, \(failed) failed",
            detail: failedTests.isEmpty ? nil : failedTests.joined(separator: "\n"),
            category: "test"
        )

        var output = "## Test Results [\(scope)]\n\n"
        output += "- Status: \(overallPassed ? "PASSED ✓" : "FAILED ✗")\n"
        output += "- Passed: \(passed)\n"
        output += "- Failed: \(failed)\n"
        if !testFilter.isEmpty { output += "- Filter: \(testFilter)\n" }
        if !failedTests.isEmpty {
            output += "\n### Failed Tests\n" + failedTests.map { "  - \($0)" }.joined(separator: "\n")
        }
        output += "\n\n### Output (truncated)\n```\n\(String(combined.suffix(2000)))\n```"

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: true, payload: [
            "title": "debug_test_check",
            "detail": "\(overallPassed ? "PASSED" : "FAILED"): \(passed) passed, \(failed) failed [\(scope)]",
            "output": output,
            "scope": scope,
            "passed": "\(passed)",
            "failed": "\(failed)",
            "exit_code": "\(exitCode)",
            "overall_status": overallPassed ? "passed" : "failed",
            "filter": testFilter
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
        let rawLimit = call.args["limit"] ?? call.args["num_results"] ?? "25"
        let numResults = min(max(Int(rawLimit) ?? 25, 1), 50)
        let allWorkspacePaths = context.workspaceContext.workspacePaths.map(\.path)
        let searchPaths: [String] = {
            if targetDirs.isEmpty {
                return allWorkspacePaths
            }
            let paths = targetDirs.flatMap { dir -> [String] in
                if (dir as NSString).isAbsolutePath {
                    return [dir]
                }
                return allWorkspacePaths.map { root in
                    (root as NSString).appendingPathComponent(dir)
                }
            }
            var deduped: [String] = []
            var seen = Set<String>()
            for path in paths where seen.insert(path).inserted {
                deduped.append(path)
            }
            return deduped
        }()

        // Primary: BM25 SemanticIndex (AST-aware chunks + inverted index)
        if let index = codebaseIndex {
            await ensureSemanticIndexReadyIfNeeded(index: index, context: context)
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
                    "count": "\(results.count)",
                    "pathScope": targetDirs.isEmpty ? "." : targetDirs.joined(separator: ",")
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

        func relativePathForDisplay(absolutePath: String) -> String {
            let normalized = (absolutePath as NSString).standardizingPath
            for root in allWorkspacePaths {
                let rootNorm = (root as NSString).standardizingPath
                if normalized == rootNorm { return (root as NSString).lastPathComponent }
                let prefix = rootNorm.hasSuffix("/") ? rootNorm : rootNorm + "/"
                if normalized.hasPrefix(prefix) {
                    let tail = String(normalized.dropFirst(prefix.count))
                    return ((root as NSString).lastPathComponent) + "/" + tail
                }
            }
            return absolutePath
        }

        var grepResults: [FallbackResult] = []
        for pattern in patterns.prefix(5) {
            for searchPath in searchPaths {
                let output = await runSemanticTextSearch(
                    pattern: pattern,
                    searchPath: searchPath,
                    workspace: searchPath
                )
                guard !output.isEmpty else { continue }

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
                    let relPath = relativePathForDisplay(absolutePath: filePath)
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
            "count": "\(top.count)",
            "pathScope": targetDirs.isEmpty ? "." : targetDirs.joined(separator: ",")
        ], startDate: startDate)
    }

    private func ensureSemanticIndexReadyIfNeeded(
        index: CodebaseIndex,
        context: ToolExecutionContext
    ) async {
        let requestedPaths = preferredWorkspacePaths(for: context)
        guard !requestedPaths.isEmpty else { return }

        let status = await index.status()

        // Wait for in-progress indexing to finish before proceeding
        if status.status == .indexing {
            Self.logger.debug("ensureSemanticIndexReady: waiting for in-progress indexing to finish")
            let _ = await index.waitUntilReady(timeoutMs: 30_000)
            return
        }

        guard shouldPerformSemanticFullReindex(statusInfo: status, requestedWorkspacePaths: requestedPaths)
        else { return }

        let _ = await index.indexWorkspace(paths: requestedPaths, excludedPaths: excludedPaths)
    }

    private func preferredWorkspacePaths(for context: ToolExecutionContext) -> [URL] {
        if !context.workspaceContext.workspacePaths.isEmpty {
            return context.workspaceContext.workspacePaths
        }
        if !workspacePaths.isEmpty {
            return workspacePaths
        }
        return [context.workspaceContext.workspacePath]
    }

    private func shouldPerformSemanticFullReindex(
        statusInfo: IndexStatusInfo,
        requestedWorkspacePaths: [URL]
    ) -> Bool {
        if statusInfo.status == .idle || statusInfo.status == .error {
            return true
        }
        let requested = normalizeWorkspacePaths(requestedWorkspacePaths)
        guard !requested.isEmpty else { return false }
        let indexed = normalizeWorkspacePaths(statusInfo.workspacePaths)
        return requested != indexed
    }

    private func normalizeWorkspacePaths(_ paths: [URL]) -> [String] {
        let values = paths.map { $0.standardizedFileURL.path }
        return normalizeWorkspacePaths(values)
    }

    private func normalizeWorkspacePaths(_ paths: [String]) -> [String] {
        var normalized = Set<String>()
        for rawPath in paths {
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let value = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            normalized.insert(value)
        }
        return normalized.sorted()
    }

    private func runSemanticTextSearch(pattern: String, searchPath: String, workspace: String) async -> String {
        let command = """
        if command -v rg >/dev/null 2>&1; then
          rg --no-heading -n --max-count=10 -i '\(shellEscaped(pattern))' '\(shellEscaped(searchPath))' --glob '!.build' --glob '!node_modules' --glob '!.git' 2>/dev/null
        else
          grep -RIn -m 10 -i -- '\(shellEscaped(pattern))' '\(shellEscaped(searchPath))' 2>/dev/null
        fi
        """
        let (output, _, _) = await shellExec(
            args: ["/bin/sh", "-lc", command],
            cwd: workspace,
            timeout: 10_000
        )
        return output
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

        let scopeRaw = call.args["scope"] ?? "full"
        let scopes = Set(scopeRaw.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let isFull = scopes.contains("full")
        let includeContent = call.args["include_file_content"]?.lowercased() == "true"

        // 1. Git status + diff + log
        if isFull || scopes.contains("git") {
            let (gitStatus, _, gitExit) = await shellExec(
                args: ["/usr/bin/git", "status", "--short", "--branch"],
                cwd: workspace, timeout: 5_000
            )
            if gitExit == 0 {
                sections.append("## Git Status\n\(gitStatus)")
            }

            let (gitDiff, _, _) = await shellExec(
                args: ["/usr/bin/git", "diff", "--stat", "HEAD"],
                cwd: workspace, timeout: 5_000
            )
            if !gitDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append("## Git Diff (stat)\n\(gitDiff)")
            }

            let (gitLog, _, _) = await shellExec(
                args: ["/usr/bin/git", "log", "--oneline", "-5"],
                cwd: workspace, timeout: 5_000
            )
            if !gitLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append("## Recent Commits\n\(gitLog)")
            }
        }

        // 2. Build errors
        if isFull || scopes.contains("build") {
            let (buildOut, buildErr, buildExit) = await shellExec(
                args: ["/usr/bin/swift", "build", "--skip-update", "2>&1"],
                cwd: workspace, timeout: 30_000
            )
            let buildOutput = (buildOut + "\n" + buildErr).trimmingCharacters(in: .whitespacesAndNewlines)
            if buildExit != 0 && !buildOutput.isEmpty {
                let truncatedBuild = String(buildOutput.prefix(3000))
                sections.append("## Build Errors (exit \(buildExit))\n```\n\(truncatedBuild)\n```")
            } else {
                sections.append("## Build Status\nClean build (exit 0)")
            }
        }

        // 3. Linter diagnostics
        if isFull || scopes.contains("lints") {
            let lintStartDate = Date()
            let lintCall = ToolCall(
                id: UUID().uuidString, name: "read_lints",
                args: ["severity": "error", "limit": "20"],
                sourceProvider: call.sourceProvider, swarmId: nil, scope: call.scope
            )
            let lintResult = await executeReadLints(call: lintCall, context: context, startDate: lintStartDate)
            if lintResult.ok {
                let errorCount = lintResult.payload["error_count"] ?? "0"
                let warningCount = lintResult.payload["warning_count"] ?? "0"
                let linter = lintResult.payload["linter"] ?? "unknown"
                var lintSection = "## Linter Diagnostics (\(linter))\nErrors: \(errorCount), Warnings: \(warningCount)"
                if let output = lintResult.payload["output"], !output.isEmpty, errorCount != "0" {
                    lintSection += "\n```\n\(String(output.prefix(2000)))\n```"

                    if includeContent {
                        let errorFiles = parseErrorFiles(from: output)
                        for (filePath, lineNum) in errorFiles.prefix(5) {
                            let fullPath = filePath.hasPrefix("/") ? filePath : workspace + "/" + filePath
                            if let fileContent = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                                let allLines = fileContent.components(separatedBy: "\n")
                                let start = max(0, lineNum - 10)
                                let end = min(allLines.count, lineNum + 10)
                                let snippet = allLines[start..<end].enumerated().map { "\(start + $0.offset + 1)| \($0.element)" }.joined(separator: "\n")
                                lintSection += "\n\n### \(filePath):\(lineNum)\n```\n\(snippet)\n```"
                            }
                        }
                    }
                }
                sections.append(lintSection)
            }
        }

        // 4. Environment info
        if isFull || scopes.contains("env") {
            var envLines: [String] = []
            let (swiftVer, _, _) = await shellExec(
                args: ["/usr/bin/swift", "--version"],
                cwd: workspace, timeout: 5_000
            )
            if !swiftVer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                envLines.append("Swift: \(swiftVer.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").first ?? swiftVer)")
            }

            let (xcodeVer, _, _) = await shellExec(
                args: ["/usr/bin/xcodebuild", "-version"],
                cwd: workspace, timeout: 5_000
            )
            if !xcodeVer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                envLines.append("Xcode: \(xcodeVer.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: ", "))")
            }

            let (sdkPath, _, _) = await shellExec(
                args: ["/usr/bin/xcrun", "--show-sdk-path"],
                cwd: workspace, timeout: 5_000
            )
            if !sdkPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                envLines.append("SDK: \(sdkPath.trimmingCharacters(in: .whitespacesAndNewlines))")
            }

            envLines.append("Platform: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            envLines.append("CPU cores: \(ProcessInfo.processInfo.activeProcessorCount)")

            sections.append("## Environment\n\(envLines.joined(separator: "\n"))")
        }

        // 5. Test listing
        if isFull || scopes.contains("tests") {
            let (testList, _, testExit) = await shellExec(
                args: ["/usr/bin/swift", "test", "list", "2>&1"],
                cwd: workspace, timeout: 15_000
            )
            let trimmed = testList.trimmingCharacters(in: .whitespacesAndNewlines)
            if testExit == 0 && !trimmed.isEmpty {
                let testLines = trimmed.components(separatedBy: "\n")
                sections.append("## Tests (\(testLines.count) test cases)\n\(testLines.prefix(30).joined(separator: "\n"))\(testLines.count > 30 ? "\n... +\(testLines.count - 30) more" : "")")
            } else if !trimmed.isEmpty {
                sections.append("## Tests\n```\n\(String(trimmed.prefix(1500)))\n```")
            }
        }

        // 6. Recent crash reports
        if isFull || scopes.contains("crashes") {
            let crashDir = NSHomeDirectory() + "/Library/Logs/DiagnosticReports"
            let fm = FileManager.default
            if fm.fileExists(atPath: crashDir) {
                let (crashFiles, _, _) = await shellExec(
                    args: ["/bin/ls", "-t", crashDir],
                    cwd: workspace, timeout: 3_000
                )
                let files = crashFiles.components(separatedBy: "\n").filter { !$0.isEmpty }
                let recentCrashes = files.prefix(5)
                if !recentCrashes.isEmpty {
                    var crashSection = "## Recent Crash Reports (\(files.count) total, showing \(recentCrashes.count))\n"
                    for crashFile in recentCrashes {
                        crashSection += "- \(crashFile)\n"
                    }
                    sections.append(crashSection)
                }
            }
        }

        // 7. Dependencies (Package.resolved)
        if isFull || scopes.contains("build") {
            let resolvedPath = workspace + "/Package.resolved"
            if FileManager.default.fileExists(atPath: resolvedPath) {
                if let resolvedContent = try? String(contentsOfFile: resolvedPath, encoding: .utf8) {
                    let truncated = String(resolvedContent.prefix(2000))
                    sections.append("## Dependencies (Package.resolved)\n```json\n\(truncated)\n```")
                }
            }
        }

        // 8. Open files
        let openFiles = context.workspaceContext.openFiles
        if !openFiles.isEmpty {
            var fileSection = "## Open Files (\(openFiles.count))\n"
            for file in openFiles {
                let lineCount = file.content.components(separatedBy: "\n").count
                fileSection += "- \(file.path) (\(lineCount) lines)\n"
            }
            sections.append(fileSection)
        }

        // 9. Active file and selection
        if let activeFile = context.workspaceContext.activeFilePath {
            sections.append("## Active File\n\(activeFile)")
        }
        if let selection = context.workspaceContext.activeSelection, !selection.isEmpty {
            let preview = selection.count > 500 ? String(selection.prefix(500)) + "..." : selection
            sections.append("## Active Selection\n```\n\(preview)\n```")
        }

        // 10. Debug log summary
        let debugSnapshot = await debugLogServer.query(limit: 5)
        if debugSnapshot.totalCount > 0 {
            let summary = await debugLogServer.sessionSummary()
            if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append("## Debug Log Summary\n\(summary)")
            }
        }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        let fullContext = sections.joined(separator: "\n\n")

        return ToolResult(ok: true, payload: [
            "title": "debug_context",
            "detail": "Debug context gathered: \(sections.count) sections [\(scopes.joined(separator: ","))]",
            "output": truncate(fullContext, maxBytes: context.policy.maxBashOutputBytes),
            "sections": "\(sections.count)",
            "scopes": scopeRaw
        ], durationMs: ms)
    }

    private func parseErrorFiles(from lintOutput: String) -> [(String, Int)] {
        var result: [(String, Int)] = []
        let lines = lintOutput.components(separatedBy: "\n")
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 3)
            if parts.count >= 3,
               let lineNum = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                let filePath = String(parts[0])
                if !result.contains(where: { $0.0 == filePath && $0.1 == lineNum }) {
                    result.append((filePath, lineNum))
                }
            }
        }
        return result
    }

    // MARK: - apply_diff

    private func executeApplyDiff(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let path = try resolveRequiredPath(call.args["path"], context: context)
        let diff = (call.args["diff"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !diff.isEmpty else {
            throw ToolRuntimeError.validation("diff is required — provide a unified diff string")
        }
        guard FileManager.default.fileExists(atPath: path) else {
            throw ToolRuntimeError.validation("File not found: \(path)")
        }

        let content = try String(contentsOfFile: path, encoding: .utf8)
        var lines = content.components(separatedBy: "\n")
        var applied = 0
        var offset = 0

        let diffLines = diff.components(separatedBy: "\n")
        var i = 0
        while i < diffLines.count {
            let line = diffLines[i]
            if line.hasPrefix("@@") {
                let header = line
                let regex = try? NSRegularExpression(pattern: #"@@ -(\d+)(?:,\d+)? \+\d+(?:,\d+)? @@"#)
                let match = regex?.firstMatch(in: header, range: NSRange(header.startIndex..., in: header))
                guard let m = match,
                      let startRange = Range(m.range(at: 1), in: header),
                      let startLine = Int(header[startRange]) else {
                    i += 1
                    continue
                }

                var hunkRemovals: [Int] = []
                var hunkAdditions: [String] = []
                var pos = startLine - 1 + offset
                i += 1

                while i < diffLines.count && !diffLines[i].hasPrefix("@@") && !diffLines[i].hasPrefix("diff ") {
                    let dl = diffLines[i]
                    if dl.hasPrefix("-") {
                        if pos < lines.count {
                            hunkRemovals.append(pos)
                        }
                        pos += 1
                    } else if dl.hasPrefix("+") {
                        hunkAdditions.append(String(dl.dropFirst()))
                    } else if dl.hasPrefix(" ") || dl.isEmpty {
                        pos += 1
                    }
                    i += 1
                }

                let insertionBase = hunkRemovals.first ?? (startLine - 1 + offset)
                for idx in hunkRemovals.sorted().reversed() where idx < lines.count {
                    lines.remove(at: idx)
                }
                let insertAt = min(lines.count, insertionBase)
                for (j, text) in hunkAdditions.enumerated() {
                    lines.insert(text, at: min(lines.count, insertAt + j))
                }

                offset += hunkAdditions.count - hunkRemovals.count
                applied += 1
            } else {
                i += 1
            }
        }

        guard applied > 0 else {
            throw ToolRuntimeError.validation("No valid diff hunks found. Use unified diff format with @@ headers.")
        }

        let newContent = lines.joined(separator: "\n")
        try newContent.write(toFile: path, atomically: true, encoding: .utf8)

        return success([
            "title": "apply_diff \((path as NSString).lastPathComponent)",
            "path": path,
            "file": path,
            "detail": "Applied \(applied) diff hunks",
            "output": "Applied \(applied) hunks to \((path as NSString).lastPathComponent)"
        ], startDate: startDate)
    }

    // MARK: - batch_read

    private func executeBatchRead(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let pathsRaw = (call.args["paths"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pathsRaw.isEmpty else {
            throw ToolRuntimeError.validation("paths is required — JSON array of file paths or comma-separated paths")
        }

        var paths: [String] = []
        if pathsRaw.hasPrefix("["),
           let data = pathsRaw.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            paths = arr
        } else {
            paths = pathsRaw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        paths = paths.filter { !$0.isEmpty }
        guard !paths.isEmpty else {
            throw ToolRuntimeError.validation("No valid file paths provided")
        }
        guard paths.count <= 20 else {
            throw ToolRuntimeError.validation("Too many files — max 20 per batch_read call")
        }

        let maxPerFile = context.policy.maxReadBytesPerFile
        var output = ""
        var readCount = 0

        for rawPath in paths {
            guard let resolvedPath = resolvePath(rawPath,
                                                 workspacePaths: context.workspaceContext.workspacePaths.map(\.path),
                                                 preferredRoot: context.workspaceContext.activeRootPath,
                                                 sandboxMode: context.policy.sandboxMode) else {
                output += "### \(rawPath)\n[error: path not allowed]\n\n"
                continue
            }

            guard let handle = FileHandle(forReadingAtPath: resolvedPath) else {
                output += "### \(rawPath)\n[error: file not found]\n\n"
                continue
            }
            defer { try? handle.close() }

            let data = (try? handle.read(upToCount: maxPerFile)) ?? Data()
            let fileContent = String(data: data, encoding: .utf8) ?? "[binary file]"
            let fileLines = fileContent.components(separatedBy: "\n")
            let lineCount = fileLines.count

            let digitWidth = max(1, String(lineCount).count)
            let numbered = fileLines.enumerated().map { idx, line in
                let num = String(idx + 1)
                let pad = String(repeating: " ", count: max(0, digitWidth - num.count))
                return "\(pad)\(num)|\(line)"
            }.joined(separator: "\n")

            output += "### \(rawPath) (\(lineCount) lines)\n\(numbered)\n\n"
            readCount += 1
        }

        return success([
            "title": "batch_read (\(readCount)/\(paths.count) files)",
            "detail": "Read \(readCount) files",
            "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes)
        ], startDate: startDate)
    }

    // MARK: - diff_files

    private func executeDiffFiles(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let file1 = (call.args["file1"] ?? call.args["path1"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let file2 = (call.args["file2"] ?? call.args["path2"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !file1.isEmpty && !file2.isEmpty else {
            return failure("file1 and file2 are required", errorCode: "validation", startDate: startDate)
        }

        let workspace = context.workspaceContext.workspacePaths.first?.path ?? "."
        let abs1 = (file1 as NSString).isAbsolutePath ? file1 : (workspace as NSString).appendingPathComponent(file1)
        let abs2 = (file2 as NSString).isAbsolutePath ? file2 : (workspace as NSString).appendingPathComponent(file2)

        let contextLines = min(Int(call.args["context"] ?? "3") ?? 3, 10)
        let result = await runShellCommand(
            "diff -u --label '\(shellEscaped((file1 as NSString).lastPathComponent))' --label '\(shellEscaped((file2 as NSString).lastPathComponent))' -U \(contextLines) '\(shellEscaped(abs1))' '\(shellEscaped(abs2))' 2>&1",
            timeout: 10_000
        )

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return success([
                "title": "diff_files",
                "detail": "Files are identical",
                "output": "Files are identical: \(file1) and \(file2)"
            ], startDate: startDate)
        }

        return success([
            "title": "diff_files \((file1 as NSString).lastPathComponent) vs \((file2 as NSString).lastPathComponent)",
            "detail": "Files differ",
            "output": truncate(trimmed, maxBytes: context.policy.maxBashOutputBytes)
        ], startDate: startDate)
    }

    // MARK: - git_status

    private func executeGitStatus(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let workspace = context.workspaceContext.workspacePaths.first?.path ?? "."

        let branchResult = await runShellCommand(
            "cd '\(shellEscaped(workspace))' && git branch --show-current 2>/dev/null",
            timeout: 5_000
        )
        let branch = branchResult.trimmingCharacters(in: .whitespacesAndNewlines)

        let statusResult = await runShellCommand(
            "cd '\(shellEscaped(workspace))' && git status --porcelain=v1 2>/dev/null",
            timeout: 5_000
        )

        let aheadBehind = await runShellCommand(
            "cd '\(shellEscaped(workspace))' && git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null",
            timeout: 5_000
        )

        let lastCommit = await runShellCommand(
            "cd '\(shellEscaped(workspace))' && git log -1 --format='%h %s' 2>/dev/null",
            timeout: 5_000
        )

        var staged: [String] = []
        var unstaged: [String] = []
        var untracked: [String] = []
        var conflicts: [String] = []

        for line in statusResult.components(separatedBy: "\n") where line.count >= 3 {
            let x = line[line.startIndex]
            let y = line[line.index(after: line.startIndex)]
            let file = String(line.dropFirst(3))

            if x == "U" || y == "U" || (x == "A" && y == "A") || (x == "D" && y == "D") {
                conflicts.append("!! \(file)")
            } else {
                if x != " " && x != "?" {
                    staged.append("\(x)  \(file)")
                }
                if y != " " && y != "?" {
                    unstaged.append(" \(y) \(file)")
                }
                if x == "?" && y == "?" {
                    untracked.append("?? \(file)")
                }
            }
        }

        var output = "## Branch: \(branch.isEmpty ? "(detached HEAD)" : branch)\n"

        let abParts = aheadBehind.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
        if abParts.count == 2, let ahead = Int(abParts[0]), let behind = Int(abParts[1]) {
            if ahead > 0 || behind > 0 {
                var trackingInfo: [String] = []
                if ahead > 0 { trackingInfo.append("\(ahead) ahead") }
                if behind > 0 { trackingInfo.append("\(behind) behind") }
                output += "Tracking: \(trackingInfo.joined(separator: ", "))\n"
            }
        }

        let commit = lastCommit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !commit.isEmpty {
            output += "Last commit: \(commit)\n"
        }

        if !conflicts.isEmpty {
            output += "\n## Conflicts (\(conflicts.count))\n\(conflicts.joined(separator: "\n"))\n"
        }
        if !staged.isEmpty {
            output += "\n## Staged (\(staged.count))\n\(staged.joined(separator: "\n"))\n"
        }
        if !unstaged.isEmpty {
            output += "\n## Unstaged (\(unstaged.count))\n\(unstaged.joined(separator: "\n"))\n"
        }
        if !untracked.isEmpty {
            output += "\n## Untracked (\(untracked.count))\n\(untracked.prefix(30).joined(separator: "\n"))\n"
            if untracked.count > 30 {
                output += "...(\(untracked.count - 30) more)\n"
            }
        }

        if staged.isEmpty && unstaged.isEmpty && untracked.isEmpty && conflicts.isEmpty {
            output += "\nClean working tree.\n"
        }

        let totalChanges = staged.count + unstaged.count + untracked.count + conflicts.count
        return success([
            "title": "git_status [\(branch.isEmpty ? "HEAD" : branch)]",
            "detail": "\(totalChanges) changes",
            "output": output.trimmingCharacters(in: .whitespacesAndNewlines)
        ], startDate: startDate)
    }

    // MARK: - git_show

    private func executeGitShow(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let ref = (call.args["commit"] ?? call.args["ref"] ?? "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = context.workspaceContext.workspacePaths.first?.path ?? "."
        let statOnly = (call.args["stat_only"] ?? "").lowercased() == "true"

        let format = statOnly ? "--stat" : "--stat -p"
        let result = await runShellCommand(
            "cd '\(shellEscaped(workspace))' && git show \(format) --format='commit %H%nAuthor: %an <%ae>%nDate: %ad%n%n%s%n%b' '\(shellEscaped(ref))' 2>&1",
            timeout: 15_000
        )

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("fatal:") {
            return failure("Commit not found: \(ref)", errorCode: "validation", startDate: startDate)
        }

        return success([
            "title": "git_show \(ref)",
            "detail": statOnly ? "stats only" : "full diff",
            "output": truncate(trimmed, maxBytes: context.policy.maxBashOutputBytes)
        ], startDate: startDate)
    }

    // MARK: - code_context

    private func executeCodeContext(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let symbol = (call.args["symbol"] ?? call.args["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !symbol.isEmpty else {
            return failure("symbol is required", errorCode: "validation", startDate: startDate)
        }

        let maxRefs = min(Int(call.args["max_refs"] ?? "15") ?? 15, 30)
        var output = ""

        if let index = codebaseIndex {
            let definitions = await index.findSymbols(query: symbol, kind: nil, limit: 5)
            if !definitions.isEmpty {
                output += "## Definition\n"
                for def in definitions.prefix(3) {
                    output += "\(def.kind.rawValue) \(def.name)"
                    if !def.signature.isEmpty { output += " — \(def.signature)" }
                    output += "\n  \(def.filePath):\(def.line)\n"
                    if let doc = def.documentation, !doc.isEmpty {
                        output += "  Doc: \(doc.prefix(200))\n"
                    }

                    let absPath: String
                    if (def.filePath as NSString).isAbsolutePath {
                        absPath = def.filePath
                    } else {
                        let ws = context.workspaceContext.workspacePaths.first?.path ?? "."
                        absPath = (ws as NSString).appendingPathComponent(def.filePath)
                    }
                    if let fh = FileHandle(forReadingAtPath: absPath) {
                        defer { try? fh.close() }
                        if let data = try? fh.read(upToCount: context.policy.maxReadBytesPerFile) {
                            let fc = String(data: data, encoding: .utf8) ?? ""
                            let allLines = fc.components(separatedBy: "\n")
                            let si = max(0, def.line - 1)
                            let ei = def.endLine > 0 ? min(allLines.count, def.endLine) : min(allLines.count, si + 20)
                            if si < allLines.count {
                                let codeSlice = allLines[si..<ei]
                                output += "  ```\n"
                                for (ci, cl) in codeSlice.enumerated() {
                                    output += "  \(si + ci + 1)|\(cl)\n"
                                }
                                output += "  ```\n"
                            }
                        }
                    }
                    output += "\n"
                }
            }

            let refs = await index.findReferences(symbolName: symbol, limit: maxRefs)
            if !refs.isEmpty {
                output += "## References (\(refs.count))\n"
                for r in refs.prefix(maxRefs) {
                    let ctx = r.contextLine.trimmingCharacters(in: .whitespaces)
                    let trimCtx = ctx.count > 100 ? String(ctx.prefix(100)) + "..." : ctx
                    output += "  \(r.filePath):\(r.line) — \(trimCtx)\n"
                }
                output += "\n"
            }

            if let firstDef = definitions.first {
                let deps = await index.fileDependencies(firstDef.filePath)
                if !deps.imports.isEmpty {
                    output += "## File imports\n"
                    for imp in deps.imports.prefix(10) {
                        output += "  \(imp)\n"
                    }
                    output += "\n"
                }
            }
        } else {
            let workspace = context.workspaceContext.workspacePaths.first?.path ?? "."
            let (grepOut, _, _) = await shellExec(
                args: ["/bin/bash", "-c", "cd '\(shellEscaped(workspace))' && rg -n --no-heading -m 20 '\\b\(shellEscaped(symbol))\\b' --glob '!.build' --glob '!node_modules' --glob '!.git' 2>/dev/null | head -30"],
                cwd: workspace,
                timeout: 10_000
            )
            let trimmedGrep = grepOut.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedGrep.isEmpty {
                output = "## References (grep fallback)\n\(trimmedGrep)\n"
            }
        }

        if output.isEmpty {
            return success([
                "title": "code_context \(symbol)",
                "detail": "No results",
                "output": "Symbol not found: \(symbol)"
            ], startDate: startDate)
        }

        return success([
            "title": "code_context \(symbol)",
            "detail": "Definition + references",
            "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes)
        ], startDate: startDate)
    }
}
