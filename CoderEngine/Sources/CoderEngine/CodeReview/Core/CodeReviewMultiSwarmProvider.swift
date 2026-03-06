import Foundation

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

/// Multi-swarm provider for Code Review: performs streaming analysis, dynamically spawns
/// parallel fix workers based on analysis findings, coordinates via file locks,
/// aggregates fixes, runs test → re-review loops.
public final class CodeReviewMultiSwarmProvider: LLMProvider, @unchecked Sendable {
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

    /// Session state actor — tracks structured review state (findings, events, phase).
    public let sessionState: CodeReviewSessionState

    public init(
        config: MultiSwarmReviewConfig,
        analysisProvider: any LLMProvider,
        executionProvider: any LLMProvider,
        executionController: ExecutionController? = nil,
        sessionState: CodeReviewSessionState? = nil
    ) {
        self.config = config
        self.analysisProvider = analysisProvider
        self.executionProvider = executionProvider
        self.executionController = executionController
        self.sessionState = sessionState ?? CodeReviewSessionState(
            config: SessionConfig(
                maxWorkers: config.maxWorkers,
                maxRounds: config.maxReviewRounds
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

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await ReviewPipelineCoordinator.shared.run(
                        prompt: prompt,
                        context: context,
                        config: config,
                        analysisProvider: analysisProvider,
                        executionProvider: executionProvider,
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
}
