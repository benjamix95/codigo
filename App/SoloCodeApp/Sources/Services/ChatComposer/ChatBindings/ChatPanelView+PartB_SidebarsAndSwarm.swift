import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @ViewBuilder
    internal var planPanelSidebar: some View {
        PlanPanelView(
            todoStore: todoStore,
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            conversationId: planPanelConversationId,
            isCurrentConversationLoading: isLoadingForCurrentConversation,
            planningState: planningState,
            planFlowPhase: planFlowPhase,
            planStreamingContent: planStreamingContent,
            clarificationQuestionnaire: planClarificationQuestionnaire,
            questionsWereVisited: planClarificationCycles > 0,
            clarificationIdentitySeed: resolveClarificationIdentitySeed(
                planClarificationCycles: planClarificationCycles,
                planConversationId: planPanelConversationId,
                globalEpoch: planQuestionToolRequestEpoch
            ),
            showHistorySection: shouldShowPlanPanelHistory(source: planPanelPresentationSource),
            workspaceSource: planPanelPresentationSource,
            onClose: {
                showPlanPanel = false
            },
            onSelectOption: { option, providerId in
                selectPlanChoice(
                    option.fullText,
                    fromPlanConversationId: planPanelConversationId,
                    providerOverrideId: providerId
                )
            },
            onCustomResponse: { response in
                handleCustomPlanResponseSelection(
                    response,
                    fromPlanConversationId: planPanelConversationId
                )
            },
            onSubmitClarificationAnswers: { answers in
                submitPlanClarificationAnswers(answers)
            },
            onBuild: { choice, providerId, allowIdleRebuild in
                executeWithPlanChoice(
                    choice,
                    fromPlanConversationId: planPanelConversationId,
                    providerOverrideId: providerId,
                    allowIdleRebuild: allowIdleRebuild
                )
            },
            onStop: {
                lastTaskEndedByManualStop = true
                interruptTask()
            },
            onHistoryEntrySelectedForBuild: {
                if planFlowPhase == .idle, planningState == .idle {
                    planFlowPhase = .readyToBuild
                }
            }
        )
        .frame(width: CGFloat(uiSettings.planPanelWidthStorage))
    }

    @ViewBuilder
    internal var debugPanelSidebar: some View {
        DebugPanelView(
            debugStore: debugStore,
            taskActivities: scopedTaskActivities(for: conversationId),
            todoStore: todoStore,
            conversationId: conversationId,
            onClose: {
                showDebugPanel = false
            },
            onStop: {
                suspendRuntimeDebugProjection(for: conversationId)
                lastTaskEndedByManualStop = true
                interruptTask()
                debugStore.resetSession()
                persistDebugState(for: conversationId)
            },
            onProceed: {
                executeDebugPipelineIntent(.continueInvestigation)
            },
            onFixed: {
                let summary = debugStore.resolutionSummary
                _ = debugStore.beginMarkFixed(summary: summary)
                guard executeDebugPipelineIntent(.resolveAfterFix(summary: summary)) else {
                    debugStore.cancelPendingMarkFixed(
                        reason: "Debug pipeline resolve preflight failed."
                    )
                    persistDebugState(for: conversationId)
                    return
                }
            },
            onSubmitDebugClarification: { submission in
                submitDebugClarificationToAgent(submission)
            }
        )
        .frame(width: CGFloat(uiSettings.debugPanelWidthStorage))
    }

    @ViewBuilder
    internal var swarmPanelSidebar: some View {
        SwarmPanelView(
            taskActivityStore: taskActivityStore,
            swarmProgressStore: swarmProgressStore,
            todoStore: todoStore,
            chatStore: chatStore,
            conversationId: conversationId,
            isTaskRunning: isLoadingForCurrentConversation,
            selectedSwarmId: $panelState.selectedSwarmId,
            swarmOrchestrator: swarmReviewSettings.$swarmOrchestrator,
            swarmWorkerBackend: swarmReviewSettings.$swarmWorkerBackend,
            onClose: {
                showSwarmPanel = false
            },
            onOpenFile: { openFilesStore.openFile($0) },
            onSyncSwarmProvider: syncSwarmProvider
        )
        .frame(width: CGFloat(uiSettings.swarmPanelWidthStorage))
    }

    internal var codeReviewPanelSidebar: some View {
        ReviewPanelHost(
            taskActivityStore: taskActivityStore,
            providerRegistry: providerRegistry,
            executionController: executionController,
            workspaceStore: workspaceStore,
            openFilesStore: openFilesStore,
            todoStore: todoStore,
            conversationId: conversationId,
            providerFactoryConfigBuilder: { [self] in providerFactoryConfig() },
            onClose: { showCodeReviewPanel = false },
            onOpenFile: { openFilesStore.openFile($0) },
            onOpenFileAtLocation: { path, line in
                openFilesStore.openFile(path)
                if let line {
                    editorNavigationDispatchStore.dispatch(
                        path: path,
                        line: line,
                        pane: .primary
                    )
                }
            }
        )
        .frame(width: CGFloat(uiSettings.codeReviewPanelWidthStorage))
    }

    @ViewBuilder
    internal var swarmDashboardArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SwarmProgressView(
                    steps: swarmProgressStore.steps(for: conversationId),
                    activities: scopedTaskActivities(for: conversationId),
                    pipelineSnapshot: snapshotPipelineConversationSnapshot,
                    isPipelineRunning: snapshotPipelineConversationSnapshot?.isRunning == true,
                    isTaskRunning: isLoadingForCurrentConversation,
                    onSelectSwarm: { swarmId in
                        showSwarmPanel = true
                        selectedSwarmId = swarmId
                    }
                )
                if uiSettings.taskPanelEnabled {
                    let hasScopedConcreteActivity = scopedTaskActivities(for: conversationId).contains {
                        TaskActivityStore.isConcreteVisibleEvent($0)
                    }
                    let hasScopedTodos = !todoStore.displayTodosForChat(for: conversationId).isEmpty
                    if hasScopedConcreteActivity || hasScopedTodos {
                        TaskActivityPanel(
                            chatStore: chatStore,
                            taskActivityStore: taskActivityStore,
                            todoStore: todoStore,
                            conversationId: conversationId,
                            coderMode: coderMode,
                            debugPhase: debugStore.phase,
                            onOpenFile: { openFilesStore.openFile($0) },
                            effectivePrimaryPath: effectiveContext.primaryPath,
                            showTodoSection: shouldShowTaskPanelTodoSection
                        )
                    } else {
                        Text("No swarm activity available.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                } else {
                    Text("Swarm activity panel hidden.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: chatColumnMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
