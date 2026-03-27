import AppKit
import CoderEngine
import os
import SwiftUI
import UniformTypeIdentifiers
func isPlanExecutionProviderIdAllowed(_ providerId: String) -> Bool {
    ProviderSupport.isUserSelectableRealProvider(id: providerId)
}

func isPlanBuildExecutionCapableProvider(_ providerId: String, registry: ProviderRegistry) -> Bool {
    ProviderSupport.isPlanBuildExecutionCapableProvider(id: providerId, registry: registry)
}

func shouldHandlePlanKeyboardShortcut(isInputFocused: Bool) -> Bool {
    _ = isInputFocused
    return false
}

func canStartPlanBuild(isLoading: Bool, phase: PlanFlowPhase) -> Bool {
    !isLoading && phase != .building
}

func shouldAllowStartingPlanBuild(
    isLoadingCurrentConversation: Bool,
    phase: PlanFlowPhase,
    activeBuildPlanConversationId: UUID?,
    hasActiveBuildTask: Bool,
    isPlanBuildCheckpointInFlight: Bool = false
) -> Bool {
    guard !isPlanBuildCheckpointInFlight else { return false }
    guard canStartPlanBuild(isLoading: isLoadingCurrentConversation, phase: phase) else {
        return false
    }
    if activeBuildPlanConversationId != nil && hasActiveBuildTask {
        return false
    }
    return true
}

func shouldClearPlanCanonicalTodosOnNewTurn(
    phase: PlanFlowPhase,
    hasActivePlanBuildTask: Bool,
    hasResumablePlanState: Bool = false
) -> Bool {
    if hasActivePlanBuildTask { return false }
    if hasResumablePlanState { return false }
    switch phase {
    case .building, .proposalReady, .readyToBuild:
        return false
    case .idle, .analyzing, .questioning, .generating:
        return true
    }
}

func isPlanBuildContext(
    conversationId: UUID?,
    phase: PlanFlowPhase,
    activeBuildPlanConversationId: UUID?,
    activeBuildAgentConversationId: UUID?
) -> Bool {
    guard let conversationId else { return false }
    if phase == .building {
        return conversationId == activeBuildPlanConversationId
            || conversationId == activeBuildAgentConversationId
    }
    return conversationId == activeBuildPlanConversationId
        || conversationId == activeBuildAgentConversationId
}

func shouldResetPlanFlowAfterPreflightFailure(
    isPlanModeRequested: Bool,
    phase: PlanFlowPhase
) -> Bool {
    guard isPlanModeRequested else { return false }
    switch phase {
    case .analyzing, .questioning, .generating:
        return true
    case .idle, .proposalReady, .readyToBuild, .building:
        return false
    }
}

func shouldMutatePlanState(
    targetConversationId: UUID,
    currentConversationId: UUID?
) -> Bool {
    targetConversationId == currentConversationId
}

func shouldResetPlanFlowAfterConversationSwitch(
    targetConversationId: UUID,
    currentConversationId: UUID?,
    phase: PlanFlowPhase
) -> Bool {
    guard targetConversationId != currentConversationId else { return false }
    switch phase {
    case .analyzing, .questioning, .generating:
        return true
    case .idle, .proposalReady, .readyToBuild, .building:
        return false
    }
}

extension ChatPanelView {
    @MainActor
    internal func cleanupPlanFlowAfterConversationSwitch(targetConversationId: UUID) {
        guard shouldResetPlanFlowAfterConversationSwitch(
            targetConversationId: targetConversationId,
            currentConversationId: conversationId,
            phase: planFlowPhase
        ) else {
            return
        }
        planFlowPhase = .idle
        planningState = .idle
        clearPlanStreamingState()
    }

    /// Quando un prefight del piano fallisce (es. prompt vuoto) restando sulla stessa conversazione,
    /// `cleanupPlanFlowAfterConversationSwitch` non fa nulla (non è un cambio thread). Serve reset esplicito.
    @MainActor
    internal func resetPlanFlowAfterAbortedPreflight(targetConversationId: UUID) {
        if shouldMutatePlanState(
            targetConversationId: targetConversationId,
            currentConversationId: conversationId
        ) {
            planFlowPhase = .idle
            planningState = .idle
            planClarificationQuestionnaire = nil
            clearPlanStreamingState()
        } else {
            cleanupPlanFlowAfterConversationSwitch(targetConversationId: targetConversationId)
        }
    }
}

func shouldHidePlanMarkdownInChat(
    shouldRoutePlanStreamToPanel: Bool,
    coderMode: CoderMode,
    shouldRunPlanInline: Bool,
    fullLooksLikePlanPayload: Bool,
    shouldHidePlanMarkdownForBuild: Bool,
    hasActivePlanContext: Bool
) -> Bool {
    guard shouldRoutePlanStreamToPanel else { return false }
    return coderMode == .plan
        || shouldRunPlanInline
        || fullLooksLikePlanPayload
        || shouldHidePlanMarkdownForBuild
        || hasActivePlanContext
}

func resolvePlanStepTargetConversationId(
    eventConversationId: UUID?,
    activeBuildPlanConversationId: UUID?,
    activeTaskConversationId: UUID?
) -> UUID? {
    eventConversationId ?? activeBuildPlanConversationId ?? activeTaskConversationId
}

func resolveTodoClearTargetConversationId(
    eventConversationId: UUID?,
    activeBuildPlanConversationId: UUID?,
    activeBuildAgentConversationId: UUID?,
    activeTaskConversationId: UUID?,
    selectedConversationId: UUID?
) -> UUID? {
    if let eventConversationId {
        if let activeBuildAgentConversationId,
           let activeBuildPlanConversationId,
           eventConversationId == activeBuildAgentConversationId {
            return activeBuildPlanConversationId
        }
        return eventConversationId
    }

    return activeBuildPlanConversationId
        ?? activeTaskConversationId
        ?? selectedConversationId
}

func shouldMirrorLegacyPlanStepIntoActiveBuildPlan(
    targetConversationId: UUID?,
    phase: PlanFlowPhase,
    activeBuildPlanConversationId: UUID?,
    activeBuildAgentConversationId: UUID?
) -> Bool {
    guard let activeBuildPlanConversationId else { return false }
    guard targetConversationId != activeBuildPlanConversationId else { return false }
    return isPlanBuildContext(
        conversationId: targetConversationId,
        phase: phase,
        activeBuildPlanConversationId: activeBuildPlanConversationId,
        activeBuildAgentConversationId: activeBuildAgentConversationId
    )
}

func resolveCanonicalPlanTodoConversationId(
    targetConversationId: UUID?,
    phase: PlanFlowPhase,
    activeBuildPlanConversationId: UUID?,
    activeBuildAgentConversationId: UUID?
) -> UUID? {
    guard isPlanBuildContext(
        conversationId: targetConversationId,
        phase: phase,
        activeBuildPlanConversationId: activeBuildPlanConversationId,
        activeBuildAgentConversationId: activeBuildAgentConversationId
    ) else {
        return targetConversationId
    }
    return activeBuildPlanConversationId ?? targetConversationId
}
