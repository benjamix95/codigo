import CoderEngine
import SwiftUI

extension SettingsView {
    func syncProviders() {
        syncOpenAI(); syncAnthropic(); syncGoogle(); syncMiniMax(); syncOpenRouter(); syncGrok()
        syncCodex(); syncClaude(); syncGemini(); syncKilo()
        syncSwarm(); syncCodeReview(); syncPlanProvider()
    }
    func syncPlanProvider() {}
    func syncSwarm() {}
    func syncCodeReview() {}
    func syncOpenAI() {
        let cfg = providerFactoryConfig()
        let effort = OpenAIAPIProvider.isReasoningModel(openaiModel) ? reasoningEffort : nil
        reregisterProviderPreservingSelection(id: "openai-api", provider:
            ProviderFactory.openAIAPIProvider(
                config: cfg,
                reasoningEffort: effort,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: ProviderFactory.subagentProviderFactoryForParent(
                    "openai-api",
                    config: cfg,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths
                )
            ))
    }
    func syncAnthropic() {
        let cfg = providerFactoryConfig()
        reregisterProviderPreservingSelection(id: "anthropic-api", provider:
            ProviderFactory.anthropicAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: ProviderFactory.subagentProviderFactoryForParent(
                    "anthropic-api",
                    config: cfg,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths
                )
            ))
    }
    func syncGoogle() {
        let cfg = providerFactoryConfig()
        reregisterProviderPreservingSelection(id: "google-api", provider:
            ProviderFactory.googleAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: ProviderFactory.subagentProviderFactoryForParent(
                    "google-api",
                    config: cfg,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths
                )
            ))
    }
    func syncMiniMax() {
        let cfg = providerFactoryConfig()
        reregisterProviderPreservingSelection(id: "minimax-api", provider:
            ProviderFactory.miniMaxAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: ProviderFactory.subagentProviderFactoryForParent(
                    "minimax-api",
                    config: cfg,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths
                )
            ))
    }
    func syncOpenRouter() {
        let cfg = providerFactoryConfig()
        reregisterProviderPreservingSelection(id: "openrouter-api", provider:
            ProviderFactory.openRouterAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: ProviderFactory.subagentProviderFactoryForParent(
                    "openrouter-api",
                    config: cfg,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths
                )
            ))
    }
    func syncGrok() {
        let cfg = providerFactoryConfig()
        reregisterProviderPreservingSelection(id: "grok-api", provider:
            ProviderFactory.grokAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: ProviderFactory.subagentProviderFactoryForParent(
                    "grok-api",
                    config: cfg,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths
                )
            ))
    }
    func syncCodex() {
        let cfg = providerFactoryConfig()
        reregisterProviderPreservingSelection(id: "codex-cli", provider:
            ProviderFactory.codexProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: ProviderFactory.subagentProviderFactoryForParent(
                    "codex-cli",
                    config: cfg,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths
                )
            ))
    }
    func syncClaude() {
        let cfg = providerFactoryConfig()
        reregisterProviderPreservingSelection(id: "claude-cli", provider:
            ProviderFactory.claudeProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: ProviderFactory.subagentProviderFactoryForParent(
                    "claude-cli",
                    config: cfg,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths
                )
            ))
        syncSwarm(); syncPlanProvider()
    }
    func syncKilo() {
        let cfg = providerFactoryConfig()
        reregisterProviderPreservingSelection(id: "kilo-cli", provider:
            ProviderFactory.kiloProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: ProviderFactory.subagentProviderFactoryForParent(
                    "kilo-cli",
                    config: cfg,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths
                )
            ))
    }
    func syncGemini() {
        let cfg = providerFactoryConfig()
        reregisterProviderPreservingSelection(id: "gemini-cli", provider:
            ProviderFactory.geminiProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: ProviderFactory.subagentProviderFactoryForParent(
                    "gemini-cli",
                    config: cfg,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths
                )
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
            kiloPath: kiloPath, kiloModel: kiloModel,
            codexPath: codexPath, codexSandbox: codexSandbox,
            codexSessionFullAccess: codexSessionFullAccess,
            codexAskForApproval: codexAskForApproval,
            codexModelOverride: codexModelOverride,
            codexReasoningEffort: codexReasoningEffort,
            codexFastMode: codexFastMode,
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
            webSearchProvider: webSearchProvider,
            braveSearchApiKey: braveSearchApiKey,
            tavilyApiKey: tavilyApiKey,
            serperApiKey: serperApiKey
        )
    }
}
