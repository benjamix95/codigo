import Foundation
import CoderEngine

extension CodigoApp {
    func registerProviders() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        if providerRegistry.provider(for: "openai-api") == nil {
            let effort = OpenAIAPIProvider.isReasoningModel(model) ? "medium" : nil
            providerRegistry.register(
                ProviderFactory.openAIAPIProvider(
                    config: cfg,
                    reasoningEffort: effort,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths,
                    subagentProviderFactory: subagentFactory
                )
            )
        }
        if providerRegistry.provider(for: "anthropic-api") == nil {
            providerRegistry.register(
                ProviderFactory.anthropicAPIProvider(
                    config: cfg,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths,
                    subagentProviderFactory: subagentFactory
                )
            )
        }
        if providerRegistry.provider(for: "google-api") == nil {
            providerRegistry.register(
                ProviderFactory.googleAPIProvider(
                    config: cfg,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths,
                    subagentProviderFactory: subagentFactory
                )
            )
        }
        if providerRegistry.provider(for: "codex-cli") == nil {
            providerRegistry.register(
                ProviderFactory.codexProvider(
                    config: cfg,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths,
                    subagentProviderFactory: subagentFactory
                )
            )
        }
        if providerRegistry.provider(for: "claude-cli") == nil {
            providerRegistry.register(
                ProviderFactory.claudeProvider(
                    config: cfg,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths,
                    subagentProviderFactory: subagentFactory
                )
            )
        }
        if providerRegistry.provider(for: "gemini-cli") == nil {
            providerRegistry.register(
                ProviderFactory.geminiProvider(
                    config: cfg,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths,
                    subagentProviderFactory: subagentFactory
                )
            )
        }
        registerMiniMax(subagentFactory: subagentFactory)
        registerOpenRouter(subagentFactory: subagentFactory)
        registerGrok(subagentFactory: subagentFactory)
        NotificationCenter.default.post(name: .providersDidRegister, object: nil)
    }

    func registerMiniMax(subagentFactory: (@Sendable () -> any LLMProvider)?) {
        providerRegistry.unregister(id: "minimax-api")
        providerRegistry.register(
            ProviderFactory.miniMaxAPIProvider(
                config: providerFactoryConfig(),
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            )
        )
    }

    func registerOpenRouter(subagentFactory: (@Sendable () -> any LLMProvider)?) {
        providerRegistry.unregister(id: "openrouter-api")
        providerRegistry.register(
            ProviderFactory.openRouterAPIProvider(
                config: providerFactoryConfig(),
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            )
        )
    }

    func registerGrok(subagentFactory: (@Sendable () -> any LLMProvider)?) {
        providerRegistry.unregister(id: "grok-api")
        providerRegistry.register(
            ProviderFactory.grokAPIProvider(
                config: providerFactoryConfig(),
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                subagentProviderFactory: subagentFactory
            )
        )
    }

    func providerFactoryConfig() -> ProviderFactoryConfig {
        let effectiveSandbox =
            codexSandbox.isEmpty
            ? (CodexConfigLoader.load().sandboxMode ?? "workspace-write") : codexSandbox
        let tools = ProviderFactory.normalizedToolList(from: claudeAllowedTools)
        return ProviderFactoryConfig(
            openaiApiKey: apiKey,
            openaiModel: model,
            anthropicApiKey: anthropicApiKey,
            anthropicModel: anthropicModel,
            googleApiKey: googleApiKey,
            googleModel: googleModel,
            minimaxApiKey: minimaxApiKey,
            minimaxModel: minimaxModel,
            openrouterApiKey: openrouterApiKey,
            openrouterModel: openrouterModel,
            grokApiKey: grokApiKey,
            grokModel: grokModel,
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
            claudeAllowedTools: tools,
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

extension Notification.Name {
    static let providersDidRegister = Notification.Name("providersDidRegister")
}
