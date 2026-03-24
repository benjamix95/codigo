import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func shouldClearThreadScopedSwarmStateAfterConversationSwitch(
    isTaskActiveForOldConversation: Bool
) -> Bool {
    !isTaskActiveForOldConversation
}

extension ChatPanelView {
    internal var rootLayout: some View {
        HStack(spacing: 6) {
            VStack(spacing: 0) {
                // Keep a non-interactive drag-safe band under the transparent titlebar.
                Color.clear
                    .frame(height: topInteractiveInset)
                    .allowsHitTesting(false)
                chatHeader

                ConnectionStatusBanner(monitor: networkMonitor)

                let scopedSwarmCards = taskActivityStore.swarmCardStates(for: conversationId)
                if coderMode == .agent
                    && (!swarmProgressStore.steps(for: conversationId).isEmpty
                        || !scopedSwarmCards.isEmpty)
                {
                    SwarmProgressView(
                        store: swarmProgressStore,
                        activities: scopedTaskActivities(for: conversationId),
                        conversationId: conversationId,
                        isTaskRunning: isLoadingForCurrentConversation,
                        onSelectSwarm: { swarmId in
                            showSwarmPanel = true
                            selectedSwarmId = swarmId
                        }
                    )
                }

                if showsSwarmViewOnly {
                    swarmDashboardArea
                } else {
                    messagesArea
                        .layoutPriority(1)
                }

                if shouldShowFinalChatActions {
                    finalChatActionsBar
                }

                // Keep the legacy task bar only when the composer is not visible (e.g. Swarm).
                if !shouldShowComposer(for: coderMode)
                    && (isLoadingForCurrentConversation
                        || isSummarizing
                        || pipelineIntegrationService.isRunning(for: conversationId))
                {
                    TaskControlBar(
                        chatStore: chatStore,
                        taskActivityStore: taskActivityStore,
                        executionController: executionController,
                        pipelineService: pipelineIntegrationService,
                        conversationId: conversationId,
                        coderMode: coderMode,
                        debugPhase: debugStore.phase,
                        isSummarizing: isSummarizing,
                        activeModeColor: activeModeColor,
                        onInterrupt: { interruptTask() }
                    )
                }

                if shouldShowComposer(for: coderMode) {
                    composerArea
                }
                if shouldShowUsageFooter(for: coderMode) {
                    usageFooterArea
                }
            }
            if showPlanPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(uiSettings.planPanelWidthStorage) }, set: { uiSettings.planPanelWidthStorage = Double($0) }),
                    minWidth: 220, maxWidth: 500, leadingEdge: true
                )
                planPanelSidebar
            }
            if showDebugPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(uiSettings.debugPanelWidthStorage) }, set: { uiSettings.debugPanelWidthStorage = Double($0) }),
                    minWidth: 240, maxWidth: 500, leadingEdge: true
                )
                debugPanelSidebar
            }
            if showSwarmPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(uiSettings.swarmPanelWidthStorage) }, set: { uiSettings.swarmPanelWidthStorage = Double($0) }),
                    minWidth: 260, maxWidth: 540, leadingEdge: true
                )
                swarmPanelSidebar
            }
            if showCodeReviewPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(uiSettings.codeReviewPanelWidthStorage) }, set: { uiSettings.codeReviewPanelWidthStorage = Double($0) }),
                    minWidth: 280, maxWidth: 560, leadingEdge: true
                )
                codeReviewPanelSidebar
            }
            if gitPanelStore.isOpen {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(uiSettings.gitPanelWidthStorage) }, set: { uiSettings.gitPanelWidthStorage = Double($0) }),
                    minWidth: 280, maxWidth: 500, leadingEdge: false
                )
                GitPanelView(
                    store: gitPanelStore,
                    effectiveContext: effectiveContext,
                    onOpenFile: { openFilesStore.openFile($0) }
                )
                .environmentObject(providerRegistry)
                .frame(width: CGFloat(uiSettings.gitPanelWidthStorage))
            }
        }
        .animation(.none, value: showPlanPanel)
        .animation(.none, value: showDebugPanel)
        .animation(.none, value: showSwarmPanel)
        .animation(.none, value: showCodeReviewPanel)
        .animation(.none, value: gitPanelStore.isOpen)
    }
}
