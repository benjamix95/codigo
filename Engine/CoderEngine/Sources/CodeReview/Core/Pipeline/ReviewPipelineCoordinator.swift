import Foundation

public actor ReviewPipelineCoordinator {
    public static let shared = ReviewPipelineCoordinator()

    public init() {}

    public func run(
        prompt: String,
        context: WorkspaceContext,
        config: MultiSwarmReviewConfig,
        analysisProvider: any LLMProvider,
        executionProvider: any LLMProvider,
        runtimeResolver: CodeReviewRuntimeResolver?,
        execController: ExecutionController?,
        fileLockCoordinator: FileLockCoordinator,
        sessionState: CodeReviewSessionState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        guard ReviewCoreBridge.isEnabled else {
            throw CodeReviewMultiSwarmProvider.ReviewPipelineError.analysisTransportFailed(
                "Rust review pipeline required but unavailable."
            )
        }
        try await ReviewPipelineRustDriver(
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
        ).run()
    }

}
