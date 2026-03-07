import CoderEngine
import Foundation

extension ProviderFactory {
    static func codeReviewEnabledPhases(
        sessionConfig: SessionConfig
    ) -> ReviewEnabledPhase {
        sessionConfig.analysisOnly ? .analysisOnly : .analysisAndExecution
    }

    static func codeReviewMultiSwarmProvider(
        config: ProviderFactoryConfig,
        executionController: ExecutionController?,
        agentProviderId: String?,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        sessionState: CodeReviewSessionState? = nil,
        initialSessionConfig: SessionConfig? = nil
    ) -> CodeReviewMultiSwarmProvider? {
        let fallbackSessionConfig = SessionConfig(
            maxWorkers: config.codeReviewPartitions,
            maxRounds: config.codeReviewMaxRounds,
            analysisBackend: config.codeReviewAnalysisBackend,
            executionBackend: config.codeReviewExecutionBackend,
            analysisOnly: config.codeReviewAnalysisOnly
        )
        let bootSessionConfig = initialSessionConfig ?? fallbackSessionConfig
        guard let initialResources = makeCodeReviewRuntimeResources(
            baseConfig: config,
            sessionConfig: bootSessionConfig,
            executionController: executionController,
            agentProviderId: agentProviderId,
            codebaseIndex: codebaseIndex,
            workspacePaths: workspacePaths
        ) else {
            return nil
        }

        return CodeReviewMultiSwarmProvider(
            config: initialResources.config,
            analysisProvider: initialResources.analysisProvider,
            executionProvider: initialResources.executionProvider,
            executionController: executionController,
            sessionState: sessionState,
            runtimeResolver: { sessionConfig in
                makeCodeReviewRuntimeResources(
                    baseConfig: config,
                    sessionConfig: sessionConfig,
                    executionController: executionController,
                    agentProviderId: agentProviderId,
                    codebaseIndex: codebaseIndex,
                    workspacePaths: workspacePaths
                )
            }
        )
    }

    private static func makeCodeReviewRuntimeResources(
        baseConfig: ProviderFactoryConfig,
        sessionConfig: SessionConfig,
        executionController: ExecutionController?,
        agentProviderId: String?,
        codebaseIndex: CodebaseIndex?,
        workspacePaths: [URL]
    ) -> CodeReviewRuntimeResources? {
        var effectiveConfig = baseConfig
        effectiveConfig.codeReviewPartitions = sessionConfig.maxWorkers
        effectiveConfig.codeReviewMaxRounds = sessionConfig.maxRounds
        effectiveConfig.codeReviewAnalysisBackend = sessionConfig.analysisBackend
        effectiveConfig.codeReviewExecutionBackend = sessionConfig.executionBackend

        let resolvedAnalysisId = resolveSwarmBackendId(
            configuredBackendId: effectiveConfig.codeReviewAnalysisBackend,
            agentProviderId: agentProviderId
        )
        let resolvedExecutionId = resolveSwarmBackendId(
            configuredBackendId: effectiveConfig.codeReviewExecutionBackend,
            agentProviderId: agentProviderId
        )

        guard let analysisProvider = resolveSwarmBackendProvider(
            backendId: resolvedAnalysisId,
            config: effectiveConfig,
            executionController: executionController,
            executionScope: .review,
            toolPolicyOverride: toolRuntimeReadOnlyPolicy(from: effectiveConfig),
            codebaseIndex: codebaseIndex,
            workspacePaths: workspacePaths
        ) else { return nil }

        let executionProvider: any LLMProvider
        let effectiveExecutionBackendId: String
        if sessionConfig.analysisOnly {
            executionProvider = analysisProvider
            effectiveExecutionBackendId = resolvedAnalysisId
        } else {
            guard let resolvedExecutionProvider = resolveSwarmBackendProvider(
                backendId: resolvedExecutionId,
                config: effectiveConfig,
                executionController: executionController,
                executionScope: .review,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths
            ) else { return nil }
            executionProvider = resolvedExecutionProvider
            effectiveExecutionBackendId = resolvedExecutionId
        }

        let reviewConfig = MultiSwarmReviewConfig(
            maxWorkers: effectiveConfig.codeReviewPartitions,
            enabledPhases: codeReviewEnabledPhases(sessionConfig: sessionConfig),
            maxReviewRounds: effectiveConfig.codeReviewMaxRounds,
            analysisBackend: resolvedAnalysisId,
            executionBackend: effectiveExecutionBackendId
        )

        return CodeReviewRuntimeResources(
            config: reviewConfig,
            analysisProvider: analysisProvider,
            executionProvider: executionProvider
        )
    }
}
