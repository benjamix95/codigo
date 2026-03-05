import CoderEngine
import SwiftUI

extension SettingsView {
    func syncProviders() {
        syncOpenAI(); syncAnthropic(); syncGoogle(); syncMiniMax(); syncOpenRouter(); syncGrok()
        syncCodex(); syncClaude(); syncGemini()
        syncSwarm(); syncCodeReview(); syncPlanProvider()
    }
    func syncPlanProvider() {}
    func syncSwarm() {}
    func syncCodeReview() {}
    func syncOpenAI() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        let effort = OpenAIAPIProvider.isReasoningModel(openaiModel) ? reasoningEffort : nil
        reregisterProviderPreservingSelection(id: "openai-api", provider:
            ProviderFactory.openAIAPIProvider(
                config: cfg,
                reasoningEffort: effort,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            ))
    }
    func syncAnthropic() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        reregisterProviderPreservingSelection(id: "anthropic-api", provider:
            ProviderFactory.anthropicAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            ))
    }
    func syncGoogle() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        reregisterProviderPreservingSelection(id: "google-api", provider:
            ProviderFactory.googleAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            ))
    }
    func syncMiniMax() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        reregisterProviderPreservingSelection(id: "minimax-api", provider:
            ProviderFactory.miniMaxAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            ))
    }
    func syncOpenRouter() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        reregisterProviderPreservingSelection(id: "openrouter-api", provider:
            ProviderFactory.openRouterAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            ))
    }
    func syncGrok() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        reregisterProviderPreservingSelection(id: "grok-api", provider:
            ProviderFactory.grokAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            ))
    }
    func syncCodex() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        reregisterProviderPreservingSelection(id: "codex-cli", provider:
            ProviderFactory.codexProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            ))
    }
    func syncClaude() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        reregisterProviderPreservingSelection(id: "claude-cli", provider:
            ProviderFactory.claudeProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            ))
        syncSwarm(); syncPlanProvider()
    }
    func syncGemini() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        reregisterProviderPreservingSelection(id: "gemini-cli", provider:
            ProviderFactory.geminiProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            ))
    }
    func reregisterProviderPreservingSelection(id: String, provider: (any LLMProvider)?) {
        let wasSel = providerRegistry.selectedProviderId
        providerRegistry.unregister(id: id)
        if let provider {
            providerRegistry.register(provider)
        }
        if wasSel == id, provider != nil { providerRegistry.selectedProviderId = id }
    }
    func providerFactoryConfig() -> ProviderFactoryConfig {
        ProviderFactoryConfig(
            openaiApiKey: openaiApiKey, openaiModel: openaiModel,
            anthropicApiKey: anthropicApiKey, anthropicModel: anthropicModel,
            googleApiKey: googleApiKey, googleModel: googleModel,
            minimaxApiKey: minimaxApiKey, minimaxModel: minimaxModel,
            openrouterApiKey: openrouterApiKey, openrouterModel: openrouterModel,
            grokApiKey: grokApiKey, grokModel: grokModel,
            codexPath: codexPath, codexSandbox: codexSandbox,
            codexSessionFullAccess: codexSessionFullAccess,
            codexAskForApproval: codexAskForApproval,
            codexModelOverride: codexModelOverride,
            codexReasoningEffort: codexReasoningEffort,
            codexModelProvider: codexModelProvider,
            codexPreferResponsesWireAPI: codexPreferResponsesWireAPI,
            planModeBackend: planModeBackend,
            swarmOrchestrator: swarmOrchestrator, swarmWorkerBackend: swarmWorkerBackend,
            swarmEnabledRoles: swarmEnabledRoles,
            globalYolo: globalYolo,
            codeReviewPartitions: codeReviewPartitions,
            codeReviewAnalysisOnly: codeReviewAnalysisOnly,
            codeReviewMaxRounds: codeReviewMaxRounds,
            codeReviewAnalysisBackend: codeReviewAnalysisBackend,
            codeReviewExecutionBackend: codeReviewExecutionBackend,
            claudePath: claudePath, claudeModel: claudeModel,
            claudeAllowedTools: parseClaudeAllowedTools(),
            geminiCliPath: geminiCliPath, geminiModelOverride: geminiModelOverride,
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
