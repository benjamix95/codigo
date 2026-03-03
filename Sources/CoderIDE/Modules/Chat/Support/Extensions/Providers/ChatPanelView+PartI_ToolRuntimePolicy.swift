import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
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
}
