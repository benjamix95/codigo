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
        cfg.sandboxMode = codexSandbox.isEmpty ? nil : codexSandbox
        cfg.model = codexModelOverride.isEmpty ? nil : codexModelOverride
        cfg.modelReasoningEffort = codexReasoningEffort.isEmpty ? nil : codexReasoningEffort
        CodexConfigLoader.save(cfg)
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
        guard !swarmProviderAutoMigrated else { return }
        if swarmOrchestrator == "openai" && swarmWorkerBackend == "codex" {
            swarmOrchestrator = "auto"
            swarmWorkerBackend = "auto"
        }
        swarmProviderAutoMigrated = true
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

    internal func providerFactoryConfig() -> ProviderFactoryConfig {
        let parsedClaudeTools = ProviderFactory.normalizedToolList(from: claudeAllowedTools)
        return ProviderFactoryConfig(
            openaiApiKey: openaiApiKey,
            openaiModel: openaiModel,
            anthropicApiKey: anthropicApiKey,
            anthropicModel: anthropicModel,
            googleApiKey: googleApiKey,
            googleModel: googleModel,
            minimaxApiKey: "",
            minimaxModel: "",
            openrouterApiKey: openrouterApiKey,
            openrouterModel: openrouterModel,
            grokApiKey: "",
            grokModel: "",
            codexPath: codexPath,
            codexSandbox: effectiveSandbox,
            codexSessionFullAccess: codexSessionFullAccess,
            codexAskForApproval: codexAskForApproval,
            codexModelOverride: codexModelOverride,
            codexReasoningEffort: codexReasoningEffort,
            codexModelProvider: codexModelProvider,
            codexPreferResponsesWireAPI: codexPreferResponsesWireAPI,
            planModeBackend: planModeBackend,
            swarmOrchestrator: swarmOrchestrator,
            swarmWorkerBackend: swarmWorkerBackend,
            swarmEnabledRoles: swarmEnabledRoles,
            globalYolo: globalYolo,
            codeReviewPartitions: codeReviewPartitions,
            codeReviewAnalysisOnly: codeReviewAnalysisOnly,
            codeReviewMaxRounds: codeReviewMaxRounds,
            codeReviewAnalysisBackend: codeReviewAnalysisBackend,
            codeReviewExecutionBackend: codeReviewExecutionBackend,
            claudePath: claudePath,
            claudeModel: claudeModel,
            claudeAllowedTools: parsedClaudeTools,
            geminiCliPath: geminiCliPath,
            geminiModelOverride: geminiModelOverride,
            unifiedToolRuntimeEnabled: unifiedToolRuntimeEnabled,
            agentsHardBlockEnabled: agentsHardBlockEnabled,
            mcpEditEnforcementEnabled: mcpEditEnforcementEnabled,
            usePipelineOrchestrator: usePipelineOrchestrator,
            webSearchProvider: webSearchProvider,
            braveSearchApiKey: braveSearchApiKey,
            tavilyApiKey: tavilyApiKey,
            serperApiKey: serperApiKey
        )
    }
}
