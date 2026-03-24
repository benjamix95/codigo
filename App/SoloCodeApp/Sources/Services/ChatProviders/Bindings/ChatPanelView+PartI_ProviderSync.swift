import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func checkProviderAuth() {
        if coderMode == .ide {
            let conversation = chatStore.conversation(for: selectedConversationId)
            let threadPreferred = conversation?.preferredProviderId?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let hasBoundIDEProvider = ThreadProviderSelectionService.effectiveMode(
                for: conversation
            ) == .ide
                && (threadPreferred?.isEmpty == false)
                && ProviderSupport.isIDEProvider(id: threadPreferred)

            if hasBoundIDEProvider, let threadPreferred {
                if providerRegistry.selectedProviderId != threadPreferred {
                    DispatchQueue.main.async {
                        // Evita mutazioni rientranti durante transazioni SwiftUI/AppKit.
                        if coderMode == .ide,
                           providerRegistry.selectedProviderId != threadPreferred {
                            providerRegistry.selectedProviderId = threadPreferred
                        }
                    }
                }
            } else {
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
        }
        let selectedProviderId = providerRegistry.selectedProviderId
        if providerSettings.multiCLIAccountEnabled,
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
        let hasAnyRegisteredUserSelectableProvider = providerRegistry.providers.contains {
            ProviderSupport.isUserSelectableRealProvider(id: $0.id)
        }
        Task.detached {
            let ready = provider?.isAuthenticated() ?? false
            let anyAgentReady =
                (codexProvider?.isAuthenticated() ?? false)
                || (claudeProvider?.isAuthenticated() ?? false)
                || (geminiProvider?.isAuthenticated() ?? false)
                || hasAnyRegisteredUserSelectableProvider
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
            workspacePaths: runtimeWorkspacePaths,
            agentProviderId: "codex-cli"
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
            workspacePaths: runtimeWorkspacePaths,
            agentProviderId: "claude-cli"
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
            workspacePaths: runtimeWorkspacePaths,
            agentProviderId: "gemini-cli"
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

    internal func syncKiloProvider() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            agentProviderId: "kilo-cli"
        )
        let p = ProviderFactory.kiloProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            subagentProviderFactory: subagentFactory
        )
        reregisterProviderPreservingSelection(id: "kilo-cli", provider: p)
        checkProviderAuth()
    }

    internal func syncOpenRouterProvider() {
        let cfg = providerFactoryConfig()
        let subagentFactory = ProviderFactory.subagentProviderFactory(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: runtimeWorkspacePaths,
            agentProviderId: "openrouter-api"
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

}
