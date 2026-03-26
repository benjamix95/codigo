import Foundation

/// Enabled phases for multi-swarm review (legacy — renamed to avoid collision with Pipeline ReviewPhase)
public enum ReviewEnabledPhase: String, Sendable {
    case analysisOnly = "analysis-only"
    case analysisAndExecution = "analysis-and-execution"
}

/// Configuration for Multi-Swarm Code Review
public struct MultiSwarmReviewConfig: Sendable {
    public let maxWorkers: Int
    public let enabledPhases: ReviewEnabledPhase
    public let maxReviewRounds: Int
    public let analysisBackend: String
    public let executionBackend: String

    public init(
        maxWorkers: Int = 6,
        enabledPhases: ReviewEnabledPhase = .analysisAndExecution,
        maxReviewRounds: Int = 3,
        analysisBackend: String = "codex",
        executionBackend: String = "codex"
    ) {
        self.maxWorkers = min(12, max(1, maxWorkers))
        self.enabledPhases = enabledPhases
        self.maxReviewRounds = min(10, max(1, maxReviewRounds))
        self.analysisBackend = analysisBackend.isEmpty ? "codex" : analysisBackend
        self.executionBackend = executionBackend.isEmpty ? "codex" : executionBackend
    }
}

public struct CodeReviewMultiSwarmDebugSnapshot: Sendable, Equatable {
    public let analysisProviderId: String
    public let executionProviderId: String
    public let analysisRuntime: ToolRuntimeDebugSnapshot?
    public let executionRuntime: ToolRuntimeDebugSnapshot?

    public init(
        analysisProviderId: String,
        executionProviderId: String,
        analysisRuntime: ToolRuntimeDebugSnapshot?,
        executionRuntime: ToolRuntimeDebugSnapshot?
    ) {
        self.analysisProviderId = analysisProviderId
        self.executionProviderId = executionProviderId
        self.analysisRuntime = analysisRuntime
        self.executionRuntime = executionRuntime
    }
}

struct CodeReviewStreamTextAccumulator {
    private var chunks: [String] = []

    mutating func consume(_ event: StreamEvent) {
        switch event {
        case .textDelta(let delta):
            chunks.append(delta)
        case .textReplace(let replacement):
            chunks = [replacement]
        default:
            break
        }
    }

    var text: String {
        chunks.joined()
    }
}

/// Multi-swarm provider for Code Review: performs streaming analysis, dynamically spawns
/// parallel fix workers based on analysis findings, coordinates via file locks,
/// aggregates fixes, runs test → re-review loops.
public final class CodeReviewMultiSwarmProvider: LLMProvider, @unchecked Sendable {
    struct ReviewTask: Sendable, Codable {
        let id: String
        let description: String
        let files: [String]
        let severity: String
        let category: String?
        let lineNumber: Int?
        let endLineNumber: Int?
        let origin: FindingOrigin
        let confidence: Double?
        let evidence: String?
        let expectedInvariant: String?
        let reproOrReasoning: String?
        let sourceTool: String?
        let blocking: Bool?
    }

    enum ReviewTaskExtractionResult: Sendable {
        case tasks([ReviewTask])
        case noFixes
        case invalidJSON(reason: String)
        case noPayload(reason: String)
    }

    enum ReviewFindingsState: Sendable {
        case issues
        case clean
        case inconclusive(reason: String)
    }

    enum TestExecutionResult: Sendable {
        case passed
        case failed
        case inconclusive(reason: String)
    }

    enum ReviewFileScope: String, Sendable {
        case uncommitted
        case staged
        case workspace
        case codebase
    }

    enum ReviewPipelineError: Error, LocalizedError {
        case analysisTransportFailed(String)
        case analysisReturnedNoData

        var errorDescription: String? {
            switch self {
            case .analysisTransportFailed(let reason):
                "Analysis stream failed: \(reason)"
            case .analysisReturnedNoData:
                "Analysis completed without text output."
            }
        }
    }

    enum ExtractedReviewTasks: Sendable {
        case jsonTasks([ReviewTask])
        case invalidJSON(reason: String)
    }

    enum ParsedTasksResult: Sendable {
        case tasks([ReviewTask])
        case invalidJSON(reason: String)
    }

    struct ReReviewOutcome: Sendable {
        let text: String
        let findings: ReviewFindingsState
    }

    enum ReviewPipelineRunOutcome: Sendable, Equatable {
        case completed
        case failed(reason: String)
        case cancelled
    }

    public let id = "code-review-multi-swarm"
    public let displayName = "Code Review Multi-Swarm"
    public var attachmentCapabilities: ProviderAttachmentCapabilities {
        analysisProvider.attachmentCapabilities
    }

    private let config: MultiSwarmReviewConfig
    private let analysisProvider: any LLMProvider
    private let executionProvider: any LLMProvider
    private let executionController: ExecutionController?
    private let fileLockCoordinator = FileLockCoordinator()
    private let runtimeResolver: CodeReviewRuntimeResolver?

    /// Session state actor — tracks structured review state (findings, events, phase).
    public let sessionState: CodeReviewSessionState

    public init(
        config: MultiSwarmReviewConfig,
        analysisProvider: any LLMProvider,
        executionProvider: any LLMProvider,
        executionController: ExecutionController? = nil,
        sessionState: CodeReviewSessionState? = nil,
        runtimeResolver: CodeReviewRuntimeResolver? = nil
    ) {
        self.config = config
        self.analysisProvider = analysisProvider
        self.executionProvider = executionProvider
        self.executionController = executionController
        self.runtimeResolver = runtimeResolver
        self.sessionState = sessionState ?? CodeReviewSessionState(
            config: SessionConfig(
                maxWorkers: config.maxWorkers,
                maxRounds: config.maxReviewRounds,
                analysisOnly: config.enabledPhases == .analysisOnly
            )
        )
    }

    public func isAuthenticated() -> Bool {
        analysisProvider.isAuthenticated() && executionProvider.isAuthenticated()
    }

    public func debugSnapshot() async -> CodeReviewMultiSwarmDebugSnapshot {
        let analysisRuntime = await (analysisProvider as? ToolEnabledLLMProvider)?
            .debugToolRuntimeSnapshot()
        let executionRuntime = await (executionProvider as? ToolEnabledLLMProvider)?
            .debugToolRuntimeSnapshot()
        return CodeReviewMultiSwarmDebugSnapshot(
            analysisProviderId: analysisProvider.id,
            executionProviderId: executionProvider.id,
            analysisRuntime: analysisRuntime,
            executionRuntime: executionRuntime
        )
    }

    public func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]? = nil
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let config = self.config
        let analysisProvider = self.analysisProvider
        let executionProvider = self.executionProvider
        let execController = self.executionController
        let fileLockCoordinator = self.fileLockCoordinator
        let sessionState = self.sessionState
        let runtimeResolver = self.runtimeResolver

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await ReviewPipelineCoordinator.shared.run(
                        prompt: prompt,
                        context: context,
                        config: config,
                        analysisProvider: analysisProvider,
                        executionProvider: executionProvider,
                        runtimeResolver: runtimeResolver,
                        execController: execController,
                        fileLockCoordinator: fileLockCoordinator,
                        sessionState: sessionState,
                        continuation: continuation
                    )
                } catch {
                    await sessionState.fail(error: error.localizedDescription)
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    static func findingsStateDebugLabel(for text: String) -> String {
        switch findingsContainIssues(text) {
        case .issues: return "issues"
        case .clean: return "clean"
        case .inconclusive: return "inconclusive"
        }
    }

    static func sortedWorkerTaskIDsForDisplay(_ ids: [String]) -> [String] {
        ids.sorted(by: sortWorkerTaskIDForDisplay(_:_:))
    }

    static func sortWorkerTaskIDForDisplay(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}
