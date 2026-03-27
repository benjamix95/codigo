import SwiftUI

func shouldShowLegacyTodoCardInChat(
    coderMode: CoderMode,
    planToggleEnabled: Bool,
    planFlowPhase: PlanFlowPhase,
    planningState: PlanningState,
    hasSwarmSteps: Bool,
    hasLiveSwarmCards: Bool,
    hasPipelineProgress: Bool
) -> Bool {
    let planSurfaceActive =
        coderMode == .plan
        || planToggleEnabled
        || planFlowPhase == .analyzing
        || planFlowPhase == .questioning
        || planFlowPhase == .generating
        || planFlowPhase == .proposalReady
        || planFlowPhase == .readyToBuild
        || planFlowPhase == .building

    if planSurfaceActive {
        return false
    }
    if case .awaitingClarification = planningState { return false }
    if case .awaitingChoice = planningState { return false }

    return shouldShowLiveTodoCardInChat(
        hasSwarmSteps: hasSwarmSteps,
        hasLiveSwarmCards: hasLiveSwarmCards,
        hasPipelineProgress: hasPipelineProgress
    )
}

extension ChatPanelView {
    internal func wireTodoPlanBidirectionalSync() {
        guard todoStore.onCanonicalTodoStatusChange == nil else { return }
        todoStore.onCanonicalTodoStatusChange = { [weak chatStore, weak todoStore] _, _, canonicalConversationId in
            guard let chatStore, let todoStore else { return }
            let planConvId = canonicalConversationId
                ?? chatStore.preferredPlanConversationIdForCanonicalSync()
            if let activeId = planConvId {
                let canonicalTodos = todoStore.canonicalTodos(for: activeId)
                guard !canonicalTodos.isEmpty else { return }
                chatStore.syncPlanStepsFromCanonicalTodos(canonicalTodos, in: activeId)
            }
        }
    }

    @MainActor
    internal func requestInitialComposerFocusIfNeeded() {
        guard !didAutoFocusComposerOnLaunch else { return }
        guard selectedConversationId != nil else { return }
        didAutoFocusComposerOnLaunch = true
        composerAutoFocusTask?.cancel()
        composerAutoFocusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            isInputFocused = true
        }
    }

    var planInPanelPlaceholder: String {
        "Plan available in the Plan Panel."
    }

    var shouldShowPlanTodosInChat: Bool {
        let hasSwarmSteps = !swarmProgressStore.steps(for: conversationId).isEmpty
        let hasLiveSwarmCards = !taskActivityStore.swarmCardStates(for: conversationId).isEmpty
        let hasPipelineProgress = pipelineIntegrationService.isRunning(for: conversationId)
        return shouldShowLegacyTodoCardInChat(
            coderMode: coderMode,
            planToggleEnabled: planToggleEnabled,
            planFlowPhase: planFlowPhase,
            planningState: planningState,
            hasSwarmSteps: hasSwarmSteps,
            hasLiveSwarmCards: hasLiveSwarmCards,
            hasPipelineProgress: hasPipelineProgress
        )
    }

    var shouldRoutePlanStreamingToPanel: Bool {
        false
    }

    var shouldShowPlanBoardInChat: Bool {
        false
    }

    var shouldShowInlinePlanSummaryInChat: Bool {
        false
    }

    var shouldShowPlanAttachmentsInChat: Bool {
        false
    }

    var hasActivePlanFlowPhase: Bool {
        planFlowPhase == .analyzing
            || planFlowPhase == .questioning
            || planFlowPhase == .generating
            || planFlowPhase == .proposalReady
            || planFlowPhase == .readyToBuild
            || planFlowPhase == .building
    }
}
