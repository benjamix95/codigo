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
}
