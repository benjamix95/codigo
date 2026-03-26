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

                ChatPanelRootSwarmProgressSlot(
                    coderMode: coderMode,
                    conversationId: conversationId,
                    swarmSteps: snapshotRootLayoutSwarmSteps,
                    swarmCards: snapshotRootLayoutSwarmCards,
                    chromeLoading: snapshotChromeLoading,
                    activities: scopedTaskActivities(for: conversationId),
                    onSelectSwarm: { swarmId in
                        showSwarmPanel = true
                        selectedSwarmId = swarmId
                    },
                    swarmProgressStore: swarmProgressStore
                )

                if showsSwarmViewOnly {
                    swarmDashboardArea
                } else {
                    messagesArea
                        .layoutPriority(1)
                        // #region agent log
                        .modifier(
                            ChatPanelMessagesDebugModifier(
                                storeMessageCount: chatStore.conversation(for: conversationId)?.messages.count ?? -1,
                                snapshotCount: messagesConversationSnapshot?.messages.count ?? -1,
                                snapshotIsNil: messagesConversationSnapshot == nil,
                                showEmptyOverlay: shouldShowMessagesAreaEmptyState,
                                isLoading: snapshotChromeLoading
                            )
                        )
                        // #endregion
                }

                if shouldShowFinalChatActions {
                    finalChatActionsBar
                }

                // Keep the legacy task bar only when the composer is not visible (e.g. Swarm).
                if !shouldShowComposer(for: coderMode)
                    && (snapshotChromeLoading || isSummarizing)
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
                    minWidth: CGFloat(SidePanelLayoutMetrics.planMin),
                    maxWidth: CGFloat(SidePanelLayoutMetrics.planMax),
                    leadingEdge: true
                )
                planPanelSidebar
            }
            if showDebugPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(uiSettings.debugPanelWidthStorage) }, set: { uiSettings.debugPanelWidthStorage = Double($0) }),
                    minWidth: CGFloat(SidePanelLayoutMetrics.debugMin),
                    maxWidth: CGFloat(SidePanelLayoutMetrics.debugMax),
                    leadingEdge: true
                )
                debugPanelSidebar
            }
            if showSwarmPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(uiSettings.swarmPanelWidthStorage) }, set: { uiSettings.swarmPanelWidthStorage = Double($0) }),
                    minWidth: CGFloat(SidePanelLayoutMetrics.swarmMin),
                    maxWidth: CGFloat(SidePanelLayoutMetrics.swarmMax),
                    leadingEdge: true
                )
                swarmPanelSidebar
            }
            if showCodeReviewPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(uiSettings.codeReviewPanelWidthStorage) }, set: { uiSettings.codeReviewPanelWidthStorage = Double($0) }),
                    minWidth: CGFloat(SidePanelLayoutMetrics.codeReviewMin),
                    maxWidth: CGFloat(SidePanelLayoutMetrics.codeReviewMax),
                    leadingEdge: true
                )
                codeReviewPanelSidebar
            }
            if gitPanelStore.isOpen {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(uiSettings.gitPanelWidthStorage) }, set: { uiSettings.gitPanelWidthStorage = Double($0) }),
                    minWidth: CGFloat(SidePanelLayoutMetrics.gitMin),
                    maxWidth: CGFloat(SidePanelLayoutMetrics.gitMax),
                    leadingEdge: false
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
        // Disable all implicit animations on the root HStack.
        // Previously used 5 stacked .animation(.none, value:) modifiers,
        // each tracking a separate state value. Even with .none, SwiftUI
        // evaluates each modifier on every state change. A single
        // .transaction modifier is more efficient — it unconditionally
        // strips animations from all child transactions.
        .onAppear { refreshMessagesSnapshot() }
        .transaction { $0.animation = nil }
        // #region agent log
        .onChange(of: coderMode) { newMode in
            AgentDebugSessionNDJSONLog.append(
                hypothesisId: "H3",
                location: "ChatPanelView+RootLayout",
                message: "coder_mode_changed",
                data: [
                    "coderMode": "\(newMode)",
                    "showsSwarmViewOnly": "\(showsSwarmViewOnly)",
                ]
            )
        }
        // #endregion
    }
}
