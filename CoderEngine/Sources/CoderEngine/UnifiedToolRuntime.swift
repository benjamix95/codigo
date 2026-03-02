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

    func validate(call: ToolCall, normalizedName: String) throws {
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
            let action = (call.args["action"] ?? "subscribe")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !["subscribe", "unsubscribe"].contains(action) {
                throw ToolRuntimeError.validation("Invalid action '\(action)'. Use subscribe or unsubscribe.")
            }
        case "mcp_logs":
            let action = (call.args["action"] ?? "read")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !["read", "set_level", "clear"].contains(action) {
                throw ToolRuntimeError.validation("Invalid action '\(action)'. Use read, set_level, or clear.")
            }
        case "mcp_get_prompt":
            if (call.args["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ToolRuntimeError.validation("'name' is required")
            }
        case "debug_mark":
            let path = (call.args["path"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty {
                throw ToolRuntimeError.validation("path is required")
            }
            let line = Int(call.args["line"] ?? "") ?? 0
            if line <= 0 {
                throw ToolRuntimeError.validation("valid line number is required")
            }
        default:
            break
        }
    }

    func resolveRequiredPath(_ rawPath: String?, context: ToolExecutionContext) throws -> String {
        let allPaths = context.workspaceContext.workspacePaths.map(\.path)
        let preferredRoot = context.workspaceContext.activeRootPath
        guard let path = resolvePath(rawPath, workspacePaths: allPaths, preferredRoot: preferredRoot, sandboxMode: context.policy.sandboxMode) else {
            throw ToolRuntimeError.sandboxViolation("Path is not allowed by sandbox policy")
        }
        return path
    }

    func resolvePath(_ rawPath: String?, workspacePaths: [String], preferredRoot: String?, sandboxMode: String) -> String? {
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

    func validateShell(command: String, policy: ToolRuntimePolicy) throws {
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

    func buildBasePayload(call: ToolCall, normalizedName: String) -> [String: String] {
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

    func startEventTypeForTool(name: String, payload: [String: String]) -> String {
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

    func eventTypeForTool(name: String, ok: Bool, payload: [String: String]) -> String {
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

    func normalizeToolName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func shellEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    func truncate(_ input: String, maxBytes: Int) -> String {
        let data = input.data(using: .utf8) ?? Data()
        if data.count <= maxBytes { return input }
        let prefixData = data.prefix(maxBytes)
        let prefixText = String(data: prefixData, encoding: .utf8) ?? String(input.prefix(maxBytes / 2))
        return prefixText + "\n...[truncated]"
    }

    func resolveExecutablePath(
        candidates: [String],
        commandName: String,
        cwd: String
    ) async -> String? {
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        let (output, _, exitCode) = await shellExec(
            args: ["/usr/bin/which", commandName],
            cwd: cwd,
            timeout: 2_000
        )
        guard exitCode == 0 else { return nil }
        let resolved = output
            .components(separatedBy: "\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !resolved.isEmpty, FileManager.default.isExecutableFile(atPath: resolved) else {
            return nil
        }
        return resolved
    }

    func resolveRipgrepPath(cwd: String) async -> String? {
        await resolveExecutablePath(
            candidates: [
                "/usr/bin/rg",
                "/opt/homebrew/bin/rg",
                "/usr/local/bin/rg",
            ],
            commandName: "rg",
            cwd: cwd
        )
    }

    func discoverFilesContaining(_ needle: String, under rootPath: String) -> [String] {
        let fm = FileManager.default
        var matches: [String] = []

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: rootPath, isDirectory: &isDirectory) else {
            return []
        }

        if !isDirectory.boolValue {
            if let content = try? String(contentsOfFile: rootPath, encoding: .utf8), content.contains(needle) {
                return [rootPath]
            }
            return []
        }

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: rootPath),
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        let skippedDirectories: Set<String> = [".git", ".build", "node_modules", "DerivedData"]
        let maxFileSize = 1_500_000

        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            if skippedDirectories.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]) else {
                continue
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                continue
            }
            if let size = values.fileSize, size > maxFileSize {
                continue
            }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  content.contains(needle) else {
                continue
            }
            matches.append(fileURL.path)
        }

        return matches
    }

    enum HypothesisLookupResult {
        case resolved(String)
        case notFound
        case ambiguous([String])
    }

    func success(_ payload: [String: String], startDate: Date) -> ToolResult {
        ToolResult(ok: true, payload: payload, durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000)))
    }

    func failure(
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

    func buildDiffPreview(old: String, new: String) -> String {
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

    func parseJSONObject(from raw: String) throws -> Any {
        guard let data = raw.data(using: .utf8) else {
            throw ToolRuntimeError.validation("JSON patch non valido")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - Codebase Index Tool Execution

    func prettyJSON(_ obj: Any) -> String {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return String(describing: obj)
        }
        return text
    }

    func parseEmbeddedArgs(_ raw: String?) -> [String: String] {
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

    func normalizeWorkspacePaths(_ paths: [String]) -> [String] {
        var normalized = Set<String>()
        for rawPath in paths {
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let value = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            normalized.insert(value)
        }
        return normalized.sorted()
    }

}
