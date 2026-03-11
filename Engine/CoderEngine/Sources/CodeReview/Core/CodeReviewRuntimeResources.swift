import Foundation

public typealias ReviewPatchPreparationRuntime = (
    CodeReviewSessionSnapshot,
    [String],
    String
) async throws -> CodeReviewSessionSnapshot

public struct CodeReviewRuntimeResources {
    public let config: MultiSwarmReviewConfig
    public let analysisProvider: any LLMProvider
    public let executionProvider: any LLMProvider
    public let prepareVerifiedPatches: ReviewPatchPreparationRuntime?

    public init(
        config: MultiSwarmReviewConfig,
        analysisProvider: any LLMProvider,
        executionProvider: any LLMProvider,
        prepareVerifiedPatches: ReviewPatchPreparationRuntime? = nil
    ) {
        self.config = config
        self.analysisProvider = analysisProvider
        self.executionProvider = executionProvider
        self.prepareVerifiedPatches = prepareVerifiedPatches
    }
}

public typealias CodeReviewRuntimeResolver = (SessionConfig) -> CodeReviewRuntimeResources?
