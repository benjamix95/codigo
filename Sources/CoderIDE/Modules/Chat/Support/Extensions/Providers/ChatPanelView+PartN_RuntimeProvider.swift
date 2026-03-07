import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func shouldUseCodeReviewRuntimeProvider(
    coderMode: CoderMode,
    preferredOverride: Bool? = nil
) -> Bool {
    preferredOverride ?? (coderMode == .codeReviewMultiSwarm)
}

extension ChatPanelView {
    internal func resolveRuntimeProvider(
        selectedProvider: any LLMProvider,
        shouldRunPlanInline: Bool,
        forcePlanInline: Bool,
        preferCodeReviewRuntimeProvider: Bool? = nil
    ) -> (any LLMProvider)? {
        // Plan/Swarm use real selected providers, without virtual providers.
        if forcePlanInline || shouldRunPlanInline || coderMode == .plan {
            return selectedProvider
        }
        // Code Review Multi-Swarm: build dedicated multi-swarm provider
        if shouldUseCodeReviewRuntimeProvider(
            coderMode: coderMode,
            preferredOverride: preferCodeReviewRuntimeProvider
        ) {
            let cfg = providerFactoryConfig()
            let store = taskActivityStore
            let reviewConversationId = conversationId
            let initialReviewSessionConfig = pendingCodeReviewSessionConfigOverride
                ?? SessionConfig(
                    maxWorkers: cfg.codeReviewPartitions,
                    maxRounds: cfg.codeReviewMaxRounds,
                    analysisBackend: cfg.codeReviewAnalysisBackend,
                    executionBackend: cfg.codeReviewExecutionBackend
                )
            let sessionState = CodeReviewSessionState(
                conversationId: reviewConversationId,
                config: initialReviewSessionConfig,
                onStateChange: { snapshot in
                    Task { @MainActor in
                        await ReviewSessionRegistry.shared.recordSnapshot(snapshot)
                        store.ingestCodeReviewSnapshot(
                            snapshot,
                            conversationId: reviewConversationId
                        )
                    }
                }
            )
            if let multiSwarm = ProviderFactory.codeReviewMultiSwarmProvider(
                config: cfg,
                executionController: executionController,
                agentProviderId: providerRegistry.selectedProviderId,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths,
                sessionState: sessionState,
                initialSessionConfig: initialReviewSessionConfig
            ) {
                pendingCodeReviewSessionConfigOverride = nil
                Task {
                    await ReviewSessionRegistry.shared.register(sessionState)
                    let snapshot = await sessionState.snapshot()
                    await MainActor.run {
                        taskActivityStore.ingestCodeReviewSnapshot(
                            snapshot,
                            conversationId: reviewConversationId
                        )
                    }
                }
                return multiSwarm
            }
            // Factory returned nil — surface the error in chat so the user knows.
            // Common cause: API key missing for the selected backend.
            let analysisBackend = initialReviewSessionConfig.analysisBackend
            let executionBackend = initialReviewSessionConfig.executionBackend
            let msg = "[Code Review] Failed to create multi-swarm provider (analysis: \(analysisBackend), execution: \(executionBackend)). Check your API keys in Settings."
            print("[CodeReview] WARNING: \(msg)")
            pendingCodeReviewSessionConfigOverride = nil
            appendTechnicalErrorMessage(msg, in: conversationId)
            return nil
        }
        if multiCLIAccountEnabled,
            let selectedProviderId = providerRegistry.selectedProviderId,
            let kind = CLIProviderKind.fromProviderId(selectedProviderId)
        {
            // Check if all accounts are exhausted
            if case .allExhausted(let reason) = cliAccountRouter.currentAvailability(
                provider: kind)
            {
                if selectedProvider.isAuthenticated() {
                    appendTechnicalErrorMessage(
                        "[Multi-account \(kind.displayName): \(reason). Falling back to the single configured CLI provider for this turn.]",
                        in: conversationId)
                    return selectedProvider
                }
                appendTechnicalErrorMessage(
                    "[Multi-account \(kind.displayName): \(reason). Configure accounts or reset limits in Settings.]",
                    in: conversationId)
                return nil
            }
            return CLIMultiAccountProviderAdapter(
                providerKind: kind,
                id: selectedProviderId,
                displayName: selectedProvider.displayName,
                router: cliAccountRouter,
                accountsStore: cliAccountsStore,
                makeProvider: { _, env in
                    let cfg = providerFactoryConfig()
                    let subagentFactory = ProviderFactory.subagentProviderFactory(
                        config: cfg,
                        executionController: executionController,
                        codebaseIndex: workspaceStore.codebaseIndex,
                        workspacePaths: runtimeWorkspacePaths,
                        agentProviderId: selectedProviderId
                    )
                    switch kind {
                    case .codex:
                        return ProviderFactory.codexProvider(
                            config: cfg, executionController: executionController,
                            codebaseIndex: workspaceStore.codebaseIndex,
                            workspacePaths: runtimeWorkspacePaths,
                            environmentOverride: env,
                            subagentProviderFactory: subagentFactory)
                    case .claude:
                        return ProviderFactory.claudeProvider(
                            config: cfg,
                            executionController: executionController,
                            codebaseIndex: workspaceStore.codebaseIndex,
                            workspacePaths: runtimeWorkspacePaths,
                            environmentOverride: env,
                            subagentProviderFactory: subagentFactory)
                    case .gemini:
                        return ProviderFactory.geminiProvider(
                            config: cfg,
                            executionController: executionController,
                            codebaseIndex: workspaceStore.codebaseIndex,
                            workspacePaths: runtimeWorkspacePaths,
                            environmentOverride: env,
                            subagentProviderFactory: subagentFactory)
                    }
                }
            )
        }
        return selectedProvider
    }
}
