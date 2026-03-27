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
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var toolTraceStore: ToolTraceStore
    @ObservedObject var pipelineIntegrationService: PipelineIntegrationService
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

struct ChatMessagesSectionView<Content: View>: View {
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var toolTraceStore: ToolTraceStore
    @ObservedObject var taskActivityStore: TaskActivityStore
    @ObservedObject var executionController: ExecutionController
    @ObservedObject var pipelineIntegrationService: PipelineIntegrationService
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

struct ChatComposerSectionView<Content: View>: View {
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var toolTraceStore: ToolTraceStore
    @ObservedObject var taskActivityStore: TaskActivityStore
    @ObservedObject var executionController: ExecutionController
    @ObservedObject var pipelineIntegrationService: PipelineIntegrationService
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

struct ChatRuntimeChromeSectionView<FinalActions: View, LegacyTaskBar: View>: View {
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var taskActivityStore: TaskActivityStore
    @ObservedObject var toolTraceStore: ToolTraceStore
    @ObservedObject var swarmProgressStore: SwarmProgressStore
    @ObservedObject var executionController: ExecutionController
    @ObservedObject var pipelineIntegrationService: PipelineIntegrationService

    let coderMode: CoderMode
    let conversationId: UUID?
    let swarmSteps: [SwarmStep]
    let swarmCards: [SwarmLiveCardState]
    let chromeLoading: Bool
    let showLegacyTaskBar: Bool
    let shouldShowFinalActions: () -> Bool
    let onSelectSwarm: (String) -> Void
    @ViewBuilder let finalActionsContent: () -> FinalActions
    @ViewBuilder let legacyTaskBarContent: () -> LegacyTaskBar

    var body: some View {
        ChatPanelRootSwarmProgressSlot(
            coderMode: coderMode,
            conversationId: conversationId,
            swarmSteps: swarmSteps,
            swarmCards: swarmCards,
            chromeLoading: chromeLoading,
            activities: taskActivityStore.activities(for: conversationId),
            onSelectSwarm: onSelectSwarm,
            swarmProgressStore: swarmProgressStore
        )

        if shouldShowFinalActions() {
            finalActionsContent()
        }

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
                ChatHeaderSectionView(
                    chatStore: chatStore,
                    todoStore: todoStore,
                    toolTraceStore: toolTraceStore,
                    pipelineIntegrationService: pipelineIntegrationService
                ) {
                    chatHeader
                }

                ConnectionStatusBanner(monitor: networkMonitor)

                ChatRuntimeChromeSectionView(
                    chatStore: chatStore,
                    taskActivityStore: taskActivityStore,
                    toolTraceStore: toolTraceStore,
                    swarmProgressStore: swarmProgressStore,
                    executionController: executionController,
                    pipelineIntegrationService: pipelineIntegrationService,
                    coderMode: coderMode,
                    conversationId: conversationId,
                    swarmSteps: snapshotRootLayoutSwarmSteps,
                    swarmCards: snapshotRootLayoutSwarmCards,
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
                )

                if showsSwarmViewOnly {
                    swarmDashboardArea
                } else {
                    ChatMessagesSectionView(
                        chatStore: chatStore,
                        todoStore: todoStore,
                        toolTraceStore: toolTraceStore,
                        taskActivityStore: taskActivityStore,
                        executionController: executionController,
                        pipelineIntegrationService: pipelineIntegrationService
                    ) {
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
                }

                if shouldShowComposerArea {
                    ChatComposerSectionView(
                        chatStore: chatStore,
                        todoStore: todoStore,
                        toolTraceStore: toolTraceStore,
                        taskActivityStore: taskActivityStore,
                        executionController: executionController,
                        pipelineIntegrationService: pipelineIntegrationService
                    ) {
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
