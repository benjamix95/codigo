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
        .frame(width: CGFloat(planPanelWidthStorage))
    }

    @ViewBuilder
    internal var debugPanelSidebar: some View {
        DebugPanelView(
            debugStore: debugStore,
            taskActivities: scopedTaskActivities(for: conversationId),
            todoStore: todoStore,
            onClose: {
                debugToggleEnabled = false
                showDebugPanel = false
                if coderMode == .debug && !debugStore.phase.isActive {
                    selectMode(.agent)
                }
            },
            onSubmitQuestion: { question in
                executeDebugPipelineIntent(.startSession(summary: question))
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
            onNativeStart: {
                executeDebugNativePipelineIntent(.start)
            },
            onNativeStop: {
                executeDebugNativePipelineIntent(.stop)
            },
            onNativeRefresh: {
                executeDebugNativePipelineIntent(.refresh)
            },
            onNativeSync: {
                executeDebugNativePipelineIntent(.syncCurrentConfiguration)
            },
            onNativeApplyWatches: {
                executeDebugNativePipelineIntent(.syncWatchExpressions(debugStore.parsedNativeWatchExpressions))
            },
            onNativeStepIn: {
                executeDebugNativePipelineIntent(.stepIn)
            },
            onNativeStepOver: {
                executeDebugNativePipelineIntent(.stepOver)
            },
            onNativeStepOut: {
                executeDebugNativePipelineIntent(.stepOut)
            },
            onNativeAddBreakpoint: {
                executeDebugNativeAddBreakpointIntent()
            },
            onNativeToggleBreakpoint: { breakpointId in
                executeDebugNativeToggleBreakpointIntent(breakpointId)
            },
            onNativeRemoveBreakpoint: { breakpointId in
                executeDebugNativeRemoveBreakpointIntent(breakpointId)
            }
        )
        .frame(width: CGFloat(debugPanelWidthStorage))
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
            selectedSwarmId: $selectedSwarmId,
            swarmOrchestrator: $swarmOrchestrator,
            swarmWorkerBackend: $swarmWorkerBackend,
            onClose: {
                showSwarmPanel = false
            },
            onOpenFile: { openFilesStore.openFile($0) },
            onSyncSwarmProvider: syncSwarmProvider
        )
        .frame(width: CGFloat(swarmPanelWidthStorage))
    }

    internal var codeReviewPanelSidebar: some View {
        ReviewPanelHost(
            taskActivityStore: taskActivityStore,
            providerRegistry: providerRegistry,
            executionController: executionController,
            workspaceStore: workspaceStore,
            openFilesStore: openFilesStore,
            providerFactoryConfigBuilder: { [self] in providerFactoryConfig() },
            onClose: { showCodeReviewPanel = false },
            onOpenFile: { openFilesStore.openFile($0) }
        )
        .frame(width: CGFloat(codeReviewPanelWidthStorage))
    }

    @ViewBuilder
    internal var swarmDashboardArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
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
                if taskPanelEnabled {
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
