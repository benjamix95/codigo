import CoderEngine
import Foundation

// MARK: - Settings Sync Coordinator

/// Performs provider re-registration when settings change.
/// Reads from UserDefaults directly so sub-views do NOT need
/// DynamicProperty containers — breaking the re-render chain.
@MainActor
final class SettingsSyncCoordinator: ObservableObject {
    weak var providerRegistry: ProviderRegistry?
    weak var executionController: ExecutionController?
    weak var workspaceStore: WorkspaceStore?

    func bind(
        registry: ProviderRegistry,
        execution: ExecutionController,
        workspace: WorkspaceStore
    ) {
        providerRegistry = registry
        executionController = execution
        workspaceStore = workspace
    }

    // MARK: - Bulk Sync

    func syncAll() {
        syncOpenAI(); syncAnthropic(); syncGoogle(); syncMiniMax(); syncOpenRouter(); syncGrok()
        syncCodex(); syncClaude(); syncGemini(); syncKilo()
        syncSwarm(); syncCodeReview(); syncPlanProvider()
    }

    // MARK: - API Providers

    func syncOpenAI() {
        let cfg = ProviderFactoryConfig.fromUserDefaults()
        let model = UserDefaults.standard.string(forKey: "openai_model") ?? "gpt-4o-mini"
        let effort = OpenAIAPIProvider.isReasoningModel(model)
            ? (UserDefaults.standard.string(forKey: "reasoning_effort") ?? "medium")
            : nil
        reregister(id: "openai-api", provider:
            ProviderFactory.openAIAPIProvider(
                config: cfg,
                reasoningEffort: effort,
                executionController: executionController,
                codebaseIndex: workspaceStore?.codebaseIndex,
                workspacePaths: workspaceStore?.activeWorkspacePaths ?? [],
                subagentProviderFactory: subagentFactory("openai-api", cfg: cfg)
            ))
    }

    func syncAnthropic() {
        let cfg = ProviderFactoryConfig.fromUserDefaults()
        reregister(id: "anthropic-api", provider:
            ProviderFactory.anthropicAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore?.codebaseIndex,
                workspacePaths: workspaceStore?.activeWorkspacePaths ?? [],
                subagentProviderFactory: subagentFactory("anthropic-api", cfg: cfg)
            ))
    }

    func syncGoogle() {
        let cfg = ProviderFactoryConfig.fromUserDefaults()
        reregister(id: "google-api", provider:
            ProviderFactory.googleAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore?.codebaseIndex,
                workspacePaths: workspaceStore?.activeWorkspacePaths ?? [],
                subagentProviderFactory: subagentFactory("google-api", cfg: cfg)
            ))
    }

    func syncMiniMax() {
        let cfg = ProviderFactoryConfig.fromUserDefaults()
        reregister(id: "minimax-api", provider:
            ProviderFactory.miniMaxAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore?.codebaseIndex,
                workspacePaths: workspaceStore?.activeWorkspacePaths ?? [],
                subagentProviderFactory: subagentFactory("minimax-api", cfg: cfg)
            ))
    }

    func syncOpenRouter() {
        let cfg = ProviderFactoryConfig.fromUserDefaults()
        reregister(id: "openrouter-api", provider:
            ProviderFactory.openRouterAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore?.codebaseIndex,
                workspacePaths: workspaceStore?.activeWorkspacePaths ?? [],
                subagentProviderFactory: subagentFactory("openrouter-api", cfg: cfg)
            ))
    }

    func syncGrok() {
        let cfg = ProviderFactoryConfig.fromUserDefaults()
        reregister(id: "grok-api", provider:
            ProviderFactory.grokAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore?.codebaseIndex,
                workspacePaths: workspaceStore?.activeWorkspacePaths ?? [],
                subagentProviderFactory: subagentFactory("grok-api", cfg: cfg)
            ))
    }

    // MARK: - CLI Providers

    func syncCodex() {
        let cfg = ProviderFactoryConfig.fromUserDefaults()
        reregister(id: "codex-cli", provider:
            ProviderFactory.codexProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore?.codebaseIndex,
                workspacePaths: workspaceStore?.activeWorkspacePaths ?? [],
                subagentProviderFactory: subagentFactory("codex-cli", cfg: cfg)
            ))
    }

    func syncClaude() {
        let cfg = ProviderFactoryConfig.fromUserDefaults()
        reregister(id: "claude-cli", provider:
            ProviderFactory.claudeProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore?.codebaseIndex,
                workspacePaths: workspaceStore?.activeWorkspacePaths ?? [],
                subagentProviderFactory: subagentFactory("claude-cli", cfg: cfg)
            ))
        syncSwarm(); syncPlanProvider()
    }

    func syncGemini() {
        let cfg = ProviderFactoryConfig.fromUserDefaults()
        reregister(id: "gemini-cli", provider:
            ProviderFactory.geminiProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore?.codebaseIndex,
                workspacePaths: workspaceStore?.activeWorkspacePaths ?? [],
                subagentProviderFactory: subagentFactory("gemini-cli", cfg: cfg)
            ))
    }

    func syncKilo() {
        let cfg = ProviderFactoryConfig.fromUserDefaults()
        reregister(id: "kilo-cli", provider:
            ProviderFactory.kiloProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore?.codebaseIndex,
                workspacePaths: workspaceStore?.activeWorkspacePaths ?? [],
                subagentProviderFactory: subagentFactory("kilo-cli", cfg: cfg)
            ))
    }

    func syncPlanProvider() {}
    func syncSwarm() {}
    func syncCodeReview() {}

    // MARK: - Helpers

    private func reregister(id: String, provider: (any LLMProvider)?) {
        guard let registry = providerRegistry else { return }
        let wasSel = registry.selectedProviderId
        registry.unregister(id: id)
        if let provider { registry.register(provider) }
        if wasSel == id, provider != nil { registry.selectedProviderId = id }
    }

    private func subagentFactory(
        _ parentId: String,
        cfg: ProviderFactoryConfig
    ) -> (@Sendable () -> any LLMProvider)? {
        ProviderFactory.subagentProviderFactoryForParent(
            parentId,
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore?.codebaseIndex,
            workspacePaths: workspaceStore?.activeWorkspacePaths ?? []
        )
    }
}
