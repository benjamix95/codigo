import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func checkProviderAuth() {
        if coderMode == .ide {
            let preferred = ProviderSupport.preferredIDEProvider(in: providerRegistry)
            if providerRegistry.selectedProviderId != preferred {
                DispatchQueue.main.async {
                    // Avoid re-entrant mutations during SwiftUI/AppKit transactions (Picker/Menu).
                    if coderMode == .ide, providerRegistry.selectedProviderId != preferred {
                        providerRegistry.selectedProviderId = preferred
                    }
                }
            }
        }
        let selectedProviderId = providerRegistry.selectedProviderId
        if multiCLIAccountEnabled,
            let selectedProviderId,
            let kind = CLIProviderKind.fromProviderId(selectedProviderId)
        {
            Task { @MainActor in
                let hasAvailable =
                    cliAccountRouter.currentAvailability(provider: kind) == .available
                isProviderReady = hasAvailable
                isAnyAgentProviderReady =
                    cliAccountRouter.currentAvailability(provider: .codex) == .available
                    || cliAccountRouter.currentAvailability(provider: .claude) == .available
                    || cliAccountRouter.currentAvailability(provider: .gemini) == .available
            }
            return
        }
        checkProviderAuthGeneration += 1
        let generation = checkProviderAuthGeneration
        let provider = providerRegistry.selectedProvider
        let codexProvider = providerRegistry.provider(for: "codex-cli")
        let claudeProvider = providerRegistry.provider(for: "claude-cli")
        let geminiProvider = providerRegistry.provider(for: "gemini-cli")
        let anyRealProvider = providerRegistry.providers.first {
            ProviderSupport.isUserSelectableRealProvider(id: $0.id) && $0.isAuthenticated()
        }
        Task.detached {
            let ready = provider?.isAuthenticated() ?? false
            let anyAgentReady =
                (codexProvider?.isAuthenticated() ?? false)
                || (claudeProvider?.isAuthenticated() ?? false)
                || (geminiProvider?.isAuthenticated() ?? false)
                || (anyRealProvider != nil)
            await MainActor.run {
                guard generation == checkProviderAuthGeneration else { return }
                isProviderReady = ready
                isAnyAgentProviderReady = anyAgentReady
            }
        }
    }

    internal func syncCodexProvider() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths
        )
        let p = ProviderFactory.codexProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            subagentProviderFactory: subagentFactory
        )
        reregisterProviderPreservingSelection(id: "codex-cli", provider: p)
        syncSwarmProvider()
        syncPlanProvider()
        checkProviderAuth()
        persistCodexConfigToToml()
    }

    internal func syncClaudeProvider() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths
        )
        let p = ProviderFactory.claudeProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            subagentProviderFactory: subagentFactory
        )
        reregisterProviderPreservingSelection(id: "claude-cli", provider: p)
        syncSwarmProvider()
        syncPlanProvider()
        checkProviderAuth()
    }

    internal func syncGeminiProvider() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths
        )
        let p = ProviderFactory.geminiProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            subagentProviderFactory: subagentFactory
        )
        reregisterProviderPreservingSelection(id: "gemini-cli", provider: p)
        checkProviderAuth()
    }

    internal func syncOpenRouterProvider() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths
        )
        let p = ProviderFactory.openRouterAPIProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            subagentProviderFactory: subagentFactory
        )
        reregisterProviderPreservingSelection(id: "openrouter-api", provider: p)
        syncSwarmProvider()
        syncPlanProvider()
        checkProviderAuth()
    }

    @MainActor
    internal func scheduleToolRuntimePolicySync(immediate: Bool = false) {
        if immediate {
            toolRuntimeSyncTask?.cancel()
            toolRuntimeSyncTask = nil
            syncToolRuntimePolicy()
            return
        }

        toolRuntimeSyncTask?.cancel()
        toolRuntimeSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000) // 180ms debounce
            guard !Task.isCancelled else { return }
            syncToolRuntimePolicy()
            toolRuntimeSyncTask = nil
        }
    }

    internal func syncToolRuntimePolicy() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths
        )
        let codex = ProviderFactory.codexProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            subagentProviderFactory: subagentFactory
        )
        reregisterProviderPreservingSelection(id: "codex-cli", provider: codex)
        let claude = ProviderFactory.claudeProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            subagentProviderFactory: subagentFactory
        )
        reregisterProviderPreservingSelection(id: "claude-cli", provider: claude)
        let gemini = ProviderFactory.geminiProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            subagentProviderFactory: subagentFactory
        )
        reregisterProviderPreservingSelection(id: "gemini-cli", provider: gemini)

        if !cfg.openrouterApiKey.isEmpty {
            let p = ProviderFactory.openRouterAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            )
            reregisterProviderPreservingSelection(id: "openrouter-api", provider: p)
        }
        if !cfg.openaiApiKey.isEmpty {
            let p = ProviderFactory.openAIAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            )
            reregisterProviderPreservingSelection(id: "openai-api", provider: p)
        }
        if !cfg.anthropicApiKey.isEmpty {
            let p = ProviderFactory.anthropicAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            )
            reregisterProviderPreservingSelection(id: "anthropic-api", provider: p)
        }
        if !cfg.googleApiKey.isEmpty {
            let p = ProviderFactory.googleAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            )
            reregisterProviderPreservingSelection(id: "google-api", provider: p)
        }
        if !cfg.minimaxApiKey.isEmpty {
            let p = ProviderFactory.miniMaxAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            )
            reregisterProviderPreservingSelection(id: "minimax-api", provider: p)
        }
        if !cfg.grokApiKey.isEmpty {
            let p = ProviderFactory.grokAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            )
            reregisterProviderPreservingSelection(id: "grok-api", provider: p)
        }

        syncSwarmProvider()
        syncPlanProvider()
        checkProviderAuth()
        persistCodexConfigToToml()
        injectBrowserBridgeIntoProviders()
    }

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
        guard let conv = chatStore.conversation(for: selectedConversationId), let mode = conv.mode
        else {
            syncCoderModeToProvider(providerRegistry.selectedProviderId)
            return
        }
        coderMode = mode
        switch mode {
        case .ide:
            if let preferred = conv.preferredProviderId,
                ProviderSupport.isIDEProvider(id: preferred),
                providerRegistry.provider(for: preferred) != nil
            {
                providerRegistry.selectedProviderId = preferred
            } else {
                providerRegistry.selectedProviderId = ProviderSupport.preferredIDEProvider(
                    in: providerRegistry)
            }
        case .agent:
            if let preferred = conv.preferredProviderId,
                ProviderSupport.isAgentCompatibleProvider(id: preferred),
                providerRegistry.provider(for: preferred) != nil
            {
                providerRegistry.selectedProviderId = preferred
            } else if let current = providerRegistry.selectedProviderId,
                ProviderSupport.isAgentCompatibleProvider(id: current)
            {
                // Keep current provider if already valid for Agent
            } else {
                providerRegistry.selectedProviderId = "codex-cli"
            }
        case .codeReviewMultiSwarm, .plan:
            if let preferred = conv.preferredProviderId,
               ProviderSupport.isAgentCompatibleProvider(id: preferred),
               providerRegistry.provider(for: preferred) != nil {
                providerRegistry.selectedProviderId = preferred
            } else if let current = providerRegistry.selectedProviderId,
                      ProviderSupport.isAgentCompatibleProvider(id: current) {
                // keep current real provider
            } else {
                providerRegistry.selectedProviderId = "codex-cli"
            }
            debugToggleEnabled = false
        case .debug:
            if let preferred = conv.preferredProviderId,
               ProviderSupport.isAgentCompatibleProvider(id: preferred),
               providerRegistry.provider(for: preferred) != nil {
                providerRegistry.selectedProviderId = preferred
            } else if let current = providerRegistry.selectedProviderId,
                      ProviderSupport.isAgentCompatibleProvider(id: current) {
                // keep current real provider
            } else {
                providerRegistry.selectedProviderId = "codex-cli"
            }
            debugToggleEnabled = true
            showDebugPanel = true
        case .browser:
            if let preferred = conv.preferredProviderId,
               ProviderSupport.isAgentCompatibleProvider(id: preferred),
               providerRegistry.provider(for: preferred) != nil {
                providerRegistry.selectedProviderId = preferred
            } else if let current = providerRegistry.selectedProviderId,
                      ProviderSupport.isAgentCompatibleProvider(id: current) {
            } else {
                providerRegistry.selectedProviderId = "codex-cli"
            }
            showBrowserPanel = true
        case .mcpServer: providerRegistry.selectedProviderId = "claude-cli"
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
            webSearchProvider: webSearchProvider,
            braveSearchApiKey: braveSearchApiKey,
            tavilyApiKey: tavilyApiKey,
            serperApiKey: serperApiKey
        )
    }

}
