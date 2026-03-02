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
    public let allowMutatingTools: Bool
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
        allowMutatingTools: Bool = true,
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
        self.allowMutatingTools = allowMutatingTools
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
    static let logger = Logger(subsystem: "com.codigo.CoderEngine", category: "UnifiedToolRuntime")

    let executionController: ExecutionController?
    let executionScope: ExecutionScope
    public let mcpSessions: MCPSessionManager

    /// Codebase index tools (created lazily when needed)
    var indexTools: CodebaseIndexTools?
    /// Direct reference to CodebaseIndex for SemanticIndex access
    var codebaseIndex: CodebaseIndex?
    let workspacePaths: [URL]
    let excludedPaths: [String]

    /// Web search service (Brave Search + DuckDuckGo fallback)
    let webSearch: WebSearchService
    /// Web fetch service (HTML → Markdown)
    let webFetch: WebFetchService

    /// Debug log server for structured debug logging
    public let debugLogServer = DebugLogServer()

    /// Tracks hypothesis lifecycle for debug_hypothesize ID validation.
    var debugHypotheses: [String: DebugHypothesis] = [:]
    var debugSessionSnapshots: [String: [String: String]] = [:]
    var debugSessionStartTime: Date?
    var debugFailingTestFilters: [String] = []

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

    // MARK: - Per-Round Budget Tracking

    /// Number of tool calls executed in the current round (reset between rounds).
    var toolCallsInCurrentRound: Int = 0
    /// Per-tool-name call count in the current round (reset between rounds).
    var toolCallCountByName: [String: Int] = [:]

    /// Terminal bridge for IDE terminal integration
    weak var terminalBridge: (any TerminalBridge)?
    /// Browser bridge for integrated browser control
    weak var browserBridge: (any BrowserBridge)?

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

    func ensureIndexTools(for context: ToolExecutionContext) async -> CodebaseIndexTools {
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
    func shellExec(
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

    func runShellCommand(_ command: String, timeout: Int = 15_000) async -> String {
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

    /// Resets per-round budget counters. Call at the beginning of each tool round.
    public func resetRoundCounters() {
        toolCallsInCurrentRound = 0
        toolCallCountByName = [:]
    }

    public func execute(_ call: ToolCall, context: ToolExecutionContext) async -> [StreamEvent] {
        let normalizedName = normalizeToolName(call.name)
        let policy = context.policy

        // Budget enforcement (defense-in-depth — ToolEnabledLLMProvider also enforces)
        if toolCallsInCurrentRound >= policy.maxToolCallsPerRound {
            return [.raw(type: "tool_execution_error", payload: [
                "tool_call_id": call.id,
                "tool": normalizedName,
                "title": "Tool budget exceeded",
                "detail": "Reached tool limit per round (\(policy.maxToolCallsPerRound))",
                "status": "failed",
                "error_code": "budget_exceeded"
            ])]
        }
        let nameCount = toolCallCountByName[normalizedName, default: 0]
        if nameCount >= policy.maxRepeatedSameToolPerRound {
            return [.raw(type: "tool_execution_error", payload: [
                "tool_call_id": call.id,
                "tool": normalizedName,
                "title": "Tool repetition limit",
                "detail": "Tool '\(normalizedName)' exceeded per-round limit (\(policy.maxRepeatedSameToolPerRound))",
                "status": "failed",
                "error_code": "repetition_exceeded"
            ])]
        }
        toolCallsInCurrentRound += 1
        toolCallCountByName[normalizedName, default: 0] += 1

        let start = Date()
        let basePayload = buildBasePayload(call: call, normalizedName: normalizedName)
        let startEventType = startEventTypeForTool(name: normalizedName, payload: basePayload)

        var events: [StreamEvent] = [.raw(type: startEventType, payload: basePayload)]
        let result = await run(call, normalizedName: normalizedName, context: context, startDate: start)

        var completedPayload = result.payload
        completedPayload["tool_call_id"] = call.id
        completedPayload["tool"] = normalizedName
        completedPayload["duration_ms"] = "\(result.durationMs)"
        let existingStatus = (completedPayload["status"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if result.ok {
            if existingStatus.isEmpty {
                completedPayload["status"] = "completed"
            }
        } else {
            completedPayload["status"] = "failed"
        }
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
    func reindexModifiedFile(call: ToolCall, context: ToolExecutionContext) async {
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

    func run(
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
}
