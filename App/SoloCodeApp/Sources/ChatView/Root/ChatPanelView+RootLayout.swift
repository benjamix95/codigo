import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func shouldClearThreadScopedSwarmStateAfterConversationSwitch(
    isTaskActiveForOldConversation: Bool
) -> Bool {
    !isTaskActiveForOldConversation
}

func shouldShowLegacyChatTaskBar(
    shouldShowComposer: Bool,
    snapshotChromeLoading: Bool,
    isSummarizing: Bool
) -> Bool {
    !shouldShowComposer && (snapshotChromeLoading || isSummarizing)
}

struct ChatHeaderSectionView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

struct ChatMessagesSectionView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

struct ChatComposerSectionView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

struct ChatRuntimeChromeSectionView<FinalActions: View, LegacyTaskBar: View>: View {
    let coderMode: CoderMode
    let swarmSteps: [SwarmStep]
    let swarmCards: [SwarmLiveCardState]
    let activities: [TaskActivity]
    let pipelineSnapshot: PipelineConversationSnapshot?
    let chromeLoading: Bool
    let showLegacyTaskBar: Bool
    let shouldShowFinalActions: () -> Bool
    let onSelectSwarm: (String) -> Void
    @ViewBuilder let finalActionsContent: () -> FinalActions
    @ViewBuilder let legacyTaskBarContent: () -> LegacyTaskBar

    var body: some View {
        ChatPanelRootSwarmProgressSlot(
            coderMode: coderMode,
            swarmSteps: swarmSteps,
            swarmCards: swarmCards,
            pipelineSnapshot: pipelineSnapshot,
            chromeLoading: chromeLoading,
            activities: activities,
            onSelectSwarm: onSelectSwarm
        )

        if showLegacyTaskBar {
            legacyTaskBarContent()
        }
    }
}

extension ChatPanelView {
    internal var rootLayout: some View {
        let shouldShowComposerArea = shouldShowComposer(for: coderMode)
        let shouldShowLegacyTaskBarSection = shouldShowLegacyChatTaskBar(
            shouldShowComposer: shouldShowComposerArea,
            snapshotChromeLoading: snapshotChromeLoading,
            isSummarizing: isSummarizing
        )
        return HStack(spacing: 6) {
            VStack(spacing: 0) {
                // Keep a non-interactive drag-safe band under the transparent titlebar.
                Color.clear
                    .frame(height: topInteractiveInset)
                    .allowsHitTesting(false)
                ChatHeaderSectionView {
                    chatHeader
                }

                ConnectionStatusBanner(monitor: networkMonitor)

                ChatRuntimeChromeSectionView(
                    coderMode: coderMode,
                    swarmSteps: snapshotRootLayoutSwarmSteps,
                    swarmCards: snapshotRootLayoutSwarmCards,
                    activities: snapshotRootLayoutActivities,
                    pipelineSnapshot: snapshotPipelineConversationSnapshot,
                    chromeLoading: snapshotChromeLoading,
                    showLegacyTaskBar: shouldShowLegacyTaskBarSection,
                    shouldShowFinalActions: { shouldShowFinalChatActions },
                    onSelectSwarm: { swarmId in
                        showSwarmPanel = true
                        selectedSwarmId = swarmId
                    },
                    finalActionsContent: {
                        finalChatActionsBar
                    },
                    legacyTaskBarContent: {
                        TaskControlBar(
                            pipelineSnapshot: snapshotPipelineConversationSnapshot,
                            taskStartDate: chatStore.taskStartDate(for: conversationId),
                            isTaskActive: chatStore.isTaskActive(for: conversationId),
                            taskActivityStore: taskActivityStore,
                            executionController: executionController,
                            coderMode: coderMode,
                            isSummarizing: isSummarizing,
                            activeModeColor: activeModeColor,
                            onInterrupt: { interruptTask(for: conversationId, source: "task_control_bar") }
                        )
                    }
                )

                if showsSwarmViewOnly {
                    swarmDashboardArea
                } else {
                    ChatMessagesSectionView {
                        VStack(spacing: 0) {
                            messagesArea
                                .layoutPriority(1)
                            if ChatFinalActionsPlacementPolicy.shouldRenderBelowMessages(
                                shouldShowFinalChatActions: shouldShowFinalChatActions,
                                showsSwarmViewOnly: showsSwarmViewOnly
                            ) {
                                finalChatActionsBar
                            }
                        }
                    }
                }

                if shouldShowComposerArea {
                    ChatComposerSectionView {
                        composerArea
                    }
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
        .transaction { $0.animation = nil }
    }
}
