import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal var composerControlsRow: some View {
        coderMode == .ide ? AnyView(ideModeControlsRow) : AnyView(modeControlsRow)
    }

    @ViewBuilder
    internal var modeControlsRow: some View {
        ModeControlsBarView(
            providerRegistry: providerRegistry,
            chatStore: chatStore,
            coderMode: coderMode,
            conversationId: conversationId,
            isAnyAgentProviderReady: isAnyAgentProviderReady,
            codexModelOverride: providerSettings.$codexModelOverride,
            codexReasoningEffort: providerSettings.$codexReasoningEffort,
            codexSandbox: providerSettings.$codexSandbox,
            geminiModelOverride: providerSettings.$geminiModelOverride,
            swarmOrchestrator: swarmReviewSettings.$swarmOrchestrator,
            taskPanelEnabled: uiSettings.$taskPanelEnabled,
            showSwarmHelp: $showSwarmHelp,
            inputText: $composerState.inputText,
            planModeBackend: uiSettings.$planModeBackend,
            swarmWorkerBackend: swarmReviewSettings.$swarmWorkerBackend,
            openaiModel: providerSettings.$openaiModel,
            claudeModel: providerSettings.$claudeModel,
            openrouterModel: providerSettings.$openrouterModel,
            kiloModel: providerSettings.$kiloModel,
            codexModels: codexModels,
            geminiModels: geminiModels,
            onSyncCodexProvider: syncCodexProvider,
            onSyncClaudeProvider: syncClaudeProvider,
            onSyncGeminiProvider: syncGeminiProvider,
            onSyncSwarmProvider: syncSwarmProvider,
            onSyncPlanProvider: syncPlanProvider,
            onSyncOpenRouterProvider: syncOpenRouterProvider,
            onSyncKiloProvider: syncKiloProvider,
            onSyncToolRuntimePolicy: syncToolRuntimePolicy,
            onUserSelectedProvider: { suppressModeSyncForNextProviderChange = true },
            onDelegateToAgent: delegateToAgent,
            attachedImageURLs: attachedComposerAttachments
                .filter { $0.kind == .image }
                .map(\.url),
            planToggleEnabled: $panelState.planToggleEnabled,
            debugToggleEnabled: $panelState.debugToggleEnabled,
            swarmToggleEnabled: Binding(
                get: { showSwarmPanel },
                set: { newValue in
                    showSwarmPanel = newValue
                }
            ),
            codeReviewToggleEnabled: Binding(
                get: { showCodeReviewPanel },
                set: { newValue in
                    showCodeReviewPanel = newValue
                }
            ),
            browserToggleEnabled: Binding(
                get: { coderMode == .browser },
                set: { newValue in
                    if newValue {
                        selectMode(.browser)
                    } else if coderMode == .browser {
                        selectMode(.agent)
                    }
                }
            ),
            forcedTier: nil
        )
    }

    @ViewBuilder
    internal var ideModeControlsRow: some View {
        ModeControlsBarView(
            providerRegistry: providerRegistry,
            chatStore: chatStore,
            coderMode: coderMode,
            conversationId: conversationId,
            isAnyAgentProviderReady: isAnyAgentProviderReady,
            codexModelOverride: providerSettings.$codexModelOverride,
            codexReasoningEffort: providerSettings.$codexReasoningEffort,
            codexSandbox: providerSettings.$codexSandbox,
            geminiModelOverride: providerSettings.$geminiModelOverride,
            swarmOrchestrator: swarmReviewSettings.$swarmOrchestrator,
            taskPanelEnabled: uiSettings.$taskPanelEnabled,
            showSwarmHelp: $showSwarmHelp,
            inputText: $composerState.inputText,
            planModeBackend: uiSettings.$planModeBackend,
            swarmWorkerBackend: swarmReviewSettings.$swarmWorkerBackend,
            openaiModel: providerSettings.$openaiModel,
            claudeModel: providerSettings.$claudeModel,
            openrouterModel: providerSettings.$openrouterModel,
            kiloModel: providerSettings.$kiloModel,
            codexModels: codexModels,
            geminiModels: geminiModels,
            onSyncCodexProvider: syncCodexProvider,
            onSyncClaudeProvider: syncClaudeProvider,
            onSyncGeminiProvider: syncGeminiProvider,
            onSyncSwarmProvider: syncSwarmProvider,
            onSyncPlanProvider: syncPlanProvider,
            onSyncOpenRouterProvider: syncOpenRouterProvider,
            onSyncKiloProvider: syncKiloProvider,
            onSyncToolRuntimePolicy: syncToolRuntimePolicy,
            onUserSelectedProvider: { suppressModeSyncForNextProviderChange = true },
            onDelegateToAgent: delegateToAgent,
            attachedImageURLs: attachedComposerAttachments
                .filter { $0.kind == .image }
                .map(\.url),
            planToggleEnabled: $panelState.planToggleEnabled,
            debugToggleEnabled: $panelState.debugToggleEnabled,
            swarmToggleEnabled: Binding(
                get: { showSwarmPanel },
                set: { newValue in showSwarmPanel = newValue }
            ),
            codeReviewToggleEnabled: Binding(
                get: { showCodeReviewPanel },
                set: { newValue in showCodeReviewPanel = newValue }
            ),
            browserToggleEnabled: Binding(
                get: { coderMode == .browser },
                set: { newValue in
                    if newValue {
                        selectMode(.browser)
                    } else if coderMode == .browser {
                        selectMode(.agent)
                    }
                }
            ),
            forcedTier: .compact
        )
    }

    @ViewBuilder
    internal var usageFooterArea: some View {
        UsageFooterView(
            selectedConversationId: $selectedConversationId,
            effectiveContext: effectiveContext,
            planModeBackend: uiSettings.planModeBackend,
            swarmWorkerBackend: swarmReviewSettings.swarmWorkerBackend,
            openaiModel: providerSettings.openaiModel,
            claudeModel: providerSettings.claudeModel,
            contextRefreshTick: streaming.streamContentVersion / 12
        )
        .frame(maxWidth: chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
    }
}
