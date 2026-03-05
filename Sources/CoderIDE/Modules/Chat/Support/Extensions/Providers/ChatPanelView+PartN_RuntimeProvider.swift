import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func resolveRuntimeProvider(
        selectedProvider: any LLMProvider,
        shouldRunPlanInline: Bool,
        forcePlanInline: Bool
    ) -> (any LLMProvider)? {
        // Plan/Swarm use real selected providers, without virtual providers.
        if forcePlanInline || shouldRunPlanInline || coderMode == .plan {
            return selectedProvider
        }
        // Code Review Multi-Swarm: build dedicated multi-swarm provider
        if coderMode == .codeReviewMultiSwarm {
            let cfg = providerFactoryConfig()
            if let multiSwarm = ProviderFactory.codeReviewMultiSwarmProvider(
                config: cfg,
                executionController: executionController,
                agentProviderId: providerRegistry.selectedProviderId,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths
            ) {
                // Wire session state → TaskActivityStore bridge for LiveCard / panel
                let store = taskActivityStore
                Task {
                    await multiSwarm.sessionState.setOnStateChange { snapshot in
                        Task { @MainActor in
                            store.ingestCodeReviewSnapshot(snapshot)
                        }
                    }
                }
                return multiSwarm
            }
            // Factory returned nil — surface the error in chat so the user knows.
            // Common cause: API key missing for the selected backend.
            let analysisBackend = cfg.codeReviewAnalysisBackend
            let executionBackend = cfg.codeReviewExecutionBackend
            let msg = "[Code Review] Failed to create multi-swarm provider (analysis: \(analysisBackend), execution: \(executionBackend)). Check your API keys in Settings."
            print("[CodeReview] WARNING: \(msg)")
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
                        workspacePaths: runtimeWorkspacePaths
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
