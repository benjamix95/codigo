import CoderEngine
import Foundation

extension ProviderFactory {
    static func codeReviewMultiSwarmProvider(
        config: ProviderFactoryConfig,
        executionController: ExecutionController?,
        agentProviderId: String?,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        sessionState: CodeReviewSessionState? = nil
    ) -> CodeReviewMultiSwarmProvider? {
        let resolvedAnalysisId = resolveSwarmBackendId(
            configuredBackendId: config.codeReviewAnalysisBackend,
            agentProviderId: agentProviderId
        )
        let resolvedExecutionId = resolveSwarmBackendId(
            configuredBackendId: config.codeReviewExecutionBackend,
            agentProviderId: agentProviderId
        )

        guard let analysisProvider = resolveSwarmBackendProvider(
            backendId: resolvedAnalysisId,
            config: config,
            executionController: executionController,
            executionScope: .review,
            toolPolicyOverride: toolRuntimeReadOnlyPolicy(from: config),
            codebaseIndex: codebaseIndex,
            workspacePaths: workspacePaths
        ) else { return nil }

        guard let executionProvider = resolveSwarmBackendProvider(
            backendId: resolvedExecutionId,
            config: config,
            executionController: executionController,
            executionScope: .review,
            codebaseIndex: codebaseIndex,
            workspacePaths: workspacePaths
        ) else { return nil }

        let reviewConfig = MultiSwarmReviewConfig(
            maxWorkers: config.codeReviewPartitions,
            enabledPhases: config.codeReviewAnalysisOnly ? .analysisOnly : .analysisAndExecution,
            maxReviewRounds: config.codeReviewMaxRounds,
            analysisBackend: resolvedAnalysisId,
            executionBackend: resolvedExecutionId
        )

        return CodeReviewMultiSwarmProvider(
            config: reviewConfig,
            analysisProvider: analysisProvider,
            executionProvider: executionProvider,
            executionController: executionController,
            sessionState: sessionState
        )
    }
}
