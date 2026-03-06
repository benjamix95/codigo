import Foundation

extension CodeReviewMultiSwarmProvider {
    static func runReviewPipeline(
        prompt: String,
        context: WorkspaceContext,
        config: MultiSwarmReviewConfig,
        analysisProvider: any LLMProvider,
        executionProvider: any LLMProvider,
        execController: ExecutionController?,
        fileLockCoordinator: FileLockCoordinator,
        sessionState: CodeReviewSessionState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
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
    }
}
