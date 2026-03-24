import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func shouldAllowLegacyMainChatProviderFallback(environment: [String: String]) -> Bool {
    if environment["SOLOCODE_REVIEW_CORE_FORCE_SWIFT"] == "1"
        || environment["SOLOCODE_REVIEW_CORE_DISABLE_RUST"] == "1"
    {
        return true
    }
    return environment["XCTestConfigurationFilePath"] != nil
        || environment["XCInjectBundleInto"] != nil
        || environment["XCTestBundlePath"] != nil
}

func readOnlyPlanProviderResolution(
    baseConfig: ProviderFactoryConfig,
    selectedProviderId: String?,
    rustResolvedConfig: MainChatRustResolvedProviderConfig?
) -> (backendId: String, config: ProviderFactoryConfig) {
    var config = baseConfig
    if let rustResolvedConfig {
        switch rustResolvedConfig.providerId {
        case "codex-cli":
            config.codexModelOverride = rustResolvedConfig.model ?? config.codexModelOverride
        case "claude-cli":
            config.claudeModel = rustResolvedConfig.model ?? config.claudeModel
        case "gemini-cli":
            config.geminiModelOverride = rustResolvedConfig.model ?? config.geminiModelOverride
        case "openai-api":
            config.openaiApiKey = rustResolvedConfig.apiKey ?? config.openaiApiKey
            config.openaiModel = rustResolvedConfig.model ?? config.openaiModel
        case "anthropic-api":
            config.anthropicApiKey = rustResolvedConfig.apiKey ?? config.anthropicApiKey
            config.anthropicModel = rustResolvedConfig.model ?? config.anthropicModel
        case "google-api":
            config.googleApiKey = rustResolvedConfig.apiKey ?? config.googleApiKey
            config.googleModel = rustResolvedConfig.model ?? config.googleModel
        default:
            break
        }
        config.codexSessionFullAccess = rustResolvedConfig.codexSessionFullAccess
        config.codexSandbox = rustResolvedConfig.codexSandbox ?? config.codexSandbox
        config.claudeAllowedTools = rustResolvedConfig.claudeAllowedTools
        return (rustResolvedConfig.providerId, config)
    }

    // Legacy fallback only when Rust transport resolution is unavailable.
    config.codexSessionFullAccess = false
    config.codexSandbox = "workspace-read"
    config.claudeAllowedTools = ["Read", "Glob", "Grep"]

    let resolvedBackend = ProviderFactory.resolveSwarmBackendId(
        configuredBackendId: config.planModeBackend,
        agentProviderId: selectedProviderId
    )
    return (resolvedBackend, config)
}

func shouldUseCodeReviewRuntimeProvider(
    coderMode: CoderMode,
    preferredOverride: Bool? = nil
) -> Bool {
    preferredOverride ?? (coderMode == .codeReviewMultiSwarm)
}

extension ChatPanelView {
    private func resolveReadOnlyPlanRuntimeProvider() -> (any LLMProvider)? {
        let environment = ProcessInfo.processInfo.environment
        let allowLegacyFallback = shouldAllowLegacyMainChatProviderFallback(environment: environment)
        let baseConfig = providerFactoryConfig()
        let registryEntries = providerRegistry.providers.map {
            MainChatRuntimeProviderRegistryEntryBridge(
                id: $0.id,
                isAuthenticated: $0.isAuthenticated()
            )
        }
        let resolved = MainChatRustTransportSupport.resolveTransportConfig(
            selectedProviderId: providerRegistry.selectedProviderId,
            fallbackSelectedProviderId: providerRegistry.selectedProviderId,
            coderMode: .plan,
            shouldRunPlanInline: false,
            forcePlanInline: false,
            preferCodeReviewRuntimeProvider: nil,
            config: baseConfig,
            registryProviders: registryEntries,
            codexCLIAccounts: providerSettings.multiCLIAccountEnabled ? cliAccountSnapshots(for: .codex) : [],
            claudeCLIAccounts: providerSettings.multiCLIAccountEnabled ? cliAccountSnapshots(for: .claude) : [],
            geminiCLIAccounts: providerSettings.multiCLIAccountEnabled ? cliAccountSnapshots(for: .gemini) : []
        )
        guard resolved != nil || allowLegacyFallback else {
            appendTechnicalErrorMessage(
                "[Plan Mode] Rust transport resolution unavailable for read-only plan provider. Standard path is fail-closed outside XCTest or explicit rollback flags.",
                in: conversationId
            )
            return nil
        }
        let resolution = readOnlyPlanProviderResolution(
            baseConfig: baseConfig,
            selectedProviderId: providerRegistry.selectedProviderId,
            rustResolvedConfig: resolved
        )

        guard let provider = ProviderFactory.resolveSwarmBackendProvider(
            backendId: resolution.backendId,
            config: resolution.config,
            executionController: executionController,
            toolPolicyOverride: ProviderFactory.toolRuntimeReadOnlyPolicy(from: resolution.config),
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths
        ) else {
            appendTechnicalErrorMessage(
                "[Plan Mode] Failed to create read-only plan provider for backend '\(resolution.backendId)'. Check plan backend settings and authentication.",
                in: conversationId
            )
            return nil
        }

        return provider
    }

    internal func resolveRuntimeProvider(
        selectedProvider: any LLMProvider,
        shouldRunPlanInline: Bool,
        forcePlanInline: Bool,
        preferCodeReviewRuntimeProvider: Bool? = nil
    ) -> (any LLMProvider)? {
        // Plan mode must run with a dedicated read-only provider.
        if forcePlanInline || shouldRunPlanInline || coderMode == .plan {
            return resolveReadOnlyPlanRuntimeProvider()
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
                    executionBackend: cfg.codeReviewExecutionBackend,
                    analysisOnly: cfg.codeReviewAnalysisOnly
                )
            let sessionState = CodeReviewSessionState(
                conversationId: reviewConversationId,
                config: initialReviewSessionConfig,
                onStateChange: { snapshot in
                    Task { @MainActor in
                        await ReviewSessionRegistry.shared.recordSnapshot(snapshot)
                        store.scheduleCodeReviewSnapshotIngest(
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
                        taskActivityStore.scheduleCodeReviewSnapshotIngest(
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
            #if DEBUG
            print("[CodeReview] WARNING: \(msg)")
            #endif
            pendingCodeReviewSessionConfigOverride = nil
            appendTechnicalErrorMessage(msg, in: conversationId)
            return nil
        }
        if providerSettings.multiCLIAccountEnabled,
            let selectedProviderId = providerRegistry.selectedProviderId,
            let kind = CLIProviderKind.fromProviderId(selectedProviderId)
        {
            let availability = cliAccountRouter.currentAvailability(provider: kind)
            let availabilityStatus: String?
            let availabilityReason: String?
            switch availability {
            case .available:
                availabilityStatus = "available"
                availabilityReason = nil
            case .allExhausted(let reason):
                availabilityStatus = "all_exhausted"
                availabilityReason = reason
            }
            let cfg = providerFactoryConfig()
            let registryEntries = providerRegistry.providers.map {
                MainChatRuntimeProviderRegistryEntryBridge(
                    id: $0.id,
                    isAuthenticated: $0.isAuthenticated()
                )
            }
            let policy = MainChatRustTransportSupport.resolveTransportConfig(
                selectedProviderId: selectedProviderId,
                fallbackSelectedProviderId: selectedProvider.id,
                coderMode: coderMode,
                shouldRunPlanInline: shouldRunPlanInline,
                forcePlanInline: forcePlanInline,
                preferCodeReviewRuntimeProvider: preferCodeReviewRuntimeProvider,
                config: cfg,
                registryProviders: registryEntries,
                codexCLIAccounts: kind == .codex ? cliAccountSnapshots(for: .codex) : [],
                claudeCLIAccounts: kind == .claude ? cliAccountSnapshots(for: .claude) : [],
                geminiCLIAccounts: kind == .gemini ? cliAccountSnapshots(for: .gemini) : [],
                multiCLIAccountEnabled: true,
                providerAvailabilityStatus: availabilityStatus,
                providerAvailabilityReason: availabilityReason,
                baseAuthenticated: selectedProvider.isAuthenticated()
            )
            if let hint = policy?.userFacingHint {
                appendTechnicalErrorMessage(hint, in: conversationId)
            }
            switch policy?.executionStrategy {
            case .singleConfiguredProvider:
                return selectedProvider
            case .failClosed:
                return nil
            case .multiAccountRouter, nil:
                break
            case .selectedProvider:
                return selectedProvider
            }
            return CLIMultiAccountProviderAdapter(
                providerKind: kind,
                id: selectedProviderId,
                displayName: selectedProvider.displayName,
                router: cliAccountRouter,
                accountsStore: cliAccountsStore,
                makeProvider: { _, env in
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
