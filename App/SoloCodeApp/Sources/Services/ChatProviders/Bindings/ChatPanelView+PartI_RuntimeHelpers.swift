import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func injectBrowserBridgeIntoProviders() {
        for provider in providerRegistry.providers {
            if let toolProvider = provider as? ToolEnabledLLMProvider {
                Task {
                    await toolProvider.setBrowserBridge(browserTabManager)
                }
            }
        }
    }

    internal func injectMacOSAutomationBridgeIntoProviders() {
        for provider in providerRegistry.providers {
            if let toolProvider = provider as? ToolEnabledLLMProvider {
                Task {
                    await toolProvider.setMacOSAutomationBridge(MacOSAutomationService.shared)
                }
            }
        }
    }

    internal func reregisterProviderPreservingSelection(id: String, provider: any LLMProvider) {
        let wasSelected = providerRegistry.selectedProviderId == id
        providerRegistry.unregister(id: id)
        providerRegistry.register(provider)
        if wasSelected {
            providerRegistry.selectedProviderId = id
        }
    }

    internal func persistCodexConfigToToml() {
        var cfg = CodexConfigLoader.load()
        cfg.sandboxMode = providerSettings.codexSandbox.isEmpty ? nil : providerSettings.codexSandbox
        cfg.fastMode = CodexFastModeStore.currentValue()
        cfg.model = providerSettings.codexModelOverride.isEmpty ? nil : providerSettings.codexModelOverride
        cfg.modelReasoningEffort = providerSettings.codexReasoningEffort.isEmpty ? nil : providerSettings.codexReasoningEffort
        CodexConfigLoader.save(cfg)
        let presetEnabled = UserDefaults.standard.bool(
            forKey: CodexCustomModelProfileSync.settingsKey
        )
        CodexCustomModelProfileSync.syncManagedBlock(
            at: CodexConfigLoader.configPath,
            enabled: presetEnabled
        )
    }

    internal func syncSwarmProvider() {
        // Swarm provider is created on-demand at runtime using real providers.
        checkProviderAuth()
    }

    internal var runtimeWorkspacePaths: [URL] {
        let contextPaths = effectiveContext.folderPaths
            .map { URL(fileURLWithPath: $0) }
        if !contextPaths.isEmpty {
            return contextPaths
        }
        return workspaceStore.activeWorkspacePaths
    }

    internal func migrateSwarmProviderDefaultsIfNeeded() {
        guard !swarmReviewSettings.swarmProviderAutoMigrated else { return }
        if swarmReviewSettings.swarmOrchestrator == "openai" && swarmReviewSettings.swarmWorkerBackend == "codex" {
            swarmReviewSettings.swarmOrchestrator = "auto"
            swarmReviewSettings.swarmWorkerBackend = "auto"
        }
        swarmReviewSettings.swarmProviderAutoMigrated = true
    }

    internal func syncCodeReviewRuntimeConfig() {
        // Review provider is created on-demand at runtime using real providers.
        checkProviderAuth()
    }

    internal func syncProviderFromConversation() {
        guard let conv = chatStore.conversation(for: selectedConversationId) else {
            syncCoderModeToProvider(providerRegistry.selectedProviderId)
            return
        }

        let effectiveMode = ThreadProviderSelectionService.effectiveMode(for: conv)
        coderMode = effectiveMode

        if let resolved = ThreadProviderSelectionService.resolveProviderId(
            conversation: conv,
            currentProviderId: providerRegistry.selectedProviderId,
            registry: providerRegistry
        ) {
            providerRegistry.selectedProviderId = resolved
        }

        switch effectiveMode {
        case .codeReviewMultiSwarm, .plan:
            debugToggleEnabled = false
        case .debug:
            debugToggleEnabled = true
            showDebugPanel = true
        case .browser:
            showBrowserPanel = true
        case .agent, .ide, .mcpServer:
            break
        }
        checkProviderAuth()
    }

    internal func syncCoderModeToProvider(_ pid: String?) {
        if userModeOverrideUntilConversationChange {
            return
        }
        guard let id = pid else {
            coderMode = .agent
            planningState = .idle
            planFlowPhase = .idle
            return
        }
        if ProviderSupport.isAgentCompatibleProvider(id: id) {
            if showDebugPanel || debugStore.phase.isActive {
                coderMode = .debug
            } else {
                coderMode = .agent
            }
            planningState = .idle
            planFlowPhase = .idle
            return
        }
        if ProviderSupport.isIDEProvider(id: id) {
            coderMode = .ide
            planningState = .idle
            planFlowPhase = .idle
            return
        }
        switch id {
        case "codex-cli", "claude-cli", "gemini-cli":
            coderMode = .agent
            planningState = .idle
            planFlowPhase = .idle
        default: break
        }
    }

    internal func syncPlanProvider() {
        // Plan mode uses selected real provider at runtime.
        checkProviderAuth()
    }

    internal func resolvedTurnProviderId(
        for conversationId: UUID?,
        fallback: String = "unknown"
    ) -> String {
        guard let conversationId else {
            return providerRegistry.selectedProviderId ?? fallback
        }

        if let activeProviderId = toolRuntime.activeToolTraceTurnsByConversation[conversationId]?.providerId,
           !activeProviderId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return activeProviderId
        }

        if let runtimeProviderId = pipelineIntegrationService.providerId(for: conversationId),
           !runtimeProviderId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return runtimeProviderId
        }

        if let assistantProviderId = chatStore.conversation(for: conversationId)?
            .messages
            .last(where: { $0.role == .assistant })?
            .turnMetadata?
            .providerId,
           !assistantProviderId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return assistantProviderId
        }

        if let preferredProviderId = chatStore.conversation(for: conversationId)?.preferredProviderId,
           !preferredProviderId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return preferredProviderId
        }

        return providerRegistry.selectedProviderId ?? fallback
    }

    internal func providerFactoryConfig() -> ProviderFactoryConfig {
        let parsedClaudeTools = ProviderFactory.normalizedToolList(from: providerSettings.claudeAllowedTools)
        return ProviderFactoryConfig(
            openaiApiKey: providerSettings.openaiApiKey,
            openaiModel: providerSettings.openaiModel,
            anthropicApiKey: providerSettings.anthropicApiKey,
            anthropicModel: providerSettings.anthropicModel,
            googleApiKey: providerSettings.googleApiKey,
            googleModel: providerSettings.googleModel,
            minimaxApiKey: "",
            minimaxModel: "",
            openrouterApiKey: providerSettings.openrouterApiKey,
            openrouterModel: providerSettings.openrouterModel,
            grokApiKey: "",
            grokModel: "",
            kiloPath: providerSettings.kiloPath,
            kiloModel: providerSettings.kiloModel,
            codexPath: providerSettings.codexPath,
            codexSandbox: effectiveSandbox,
            codexSessionFullAccess: providerSettings.codexSessionFullAccess,
            codexAskForApproval: providerSettings.codexAskForApproval,
            codexModelOverride: providerSettings.codexModelOverride,
            codexReasoningEffort: providerSettings.codexReasoningEffort,
            codexFastMode: CodexFastModeStore.currentValue(),
            codexModelProvider: providerSettings.codexModelProvider,
            codexPreferResponsesWireAPI: providerSettings.codexPreferResponsesWireAPI,
            planModeBackend: uiSettings.planModeBackend,
            swarmOrchestrator: swarmReviewSettings.swarmOrchestrator,
            swarmWorkerBackend: swarmReviewSettings.swarmWorkerBackend,
            swarmEnabledRoles: swarmReviewSettings.swarmEnabledRoles,
            globalYolo: uiSettings.globalYolo,
            codeReviewPartitions: swarmReviewSettings.codeReviewPartitions,
            codeReviewAnalysisOnly: swarmReviewSettings.codeReviewAnalysisOnly,
            codeReviewMaxRounds: swarmReviewSettings.codeReviewMaxRounds,
            codeReviewAnalysisBackend: swarmReviewSettings.codeReviewAnalysisBackend,
            codeReviewExecutionBackend: swarmReviewSettings.codeReviewExecutionBackend,
            claudePath: providerSettings.claudePath,
            claudeModel: providerSettings.claudeModel,
            claudeAllowedTools: parsedClaudeTools,
            geminiCliPath: providerSettings.geminiCliPath,
            geminiModelOverride: providerSettings.geminiModelOverride,
            unifiedToolRuntimeEnabled: uiSettings.unifiedToolRuntimeEnabled,
            agentsHardBlockEnabled: uiSettings.agentsHardBlockEnabled,
            mcpEditEnforcementEnabled: uiSettings.mcpEditEnforcementEnabled,
            webSearchProvider: uiSettings.webSearchProvider,
            braveSearchApiKey: uiSettings.braveSearchApiKey,
            tavilyApiKey: uiSettings.tavilyApiKey,
            serperApiKey: uiSettings.serperApiKey
        )
    }
}
