import Foundation

public struct CodeReviewRuntimeResources {
    public let config: MultiSwarmReviewConfig
    public let analysisProvider: any LLMProvider
    public let executionProvider: any LLMProvider

    public init(
        config: MultiSwarmReviewConfig,
        analysisProvider: any LLMProvider,
        executionProvider: any LLMProvider
    ) {
        self.config = config
        self.analysisProvider = analysisProvider
        self.executionProvider = executionProvider
    }
}

public typealias CodeReviewRuntimeResolver = (SessionConfig) -> CodeReviewRuntimeResources?
