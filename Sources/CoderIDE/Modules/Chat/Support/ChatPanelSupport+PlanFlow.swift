import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func isPlanExecutionProviderIdAllowed(_ providerId: String) -> Bool {
    ProviderSupport.isUserSelectableRealProvider(id: providerId)
}

func isPlanBuildExecutionCapableProvider(_ providerId: String, registry: ProviderRegistry) -> Bool {
    ProviderSupport.isPlanBuildExecutionCapableProvider(id: providerId, registry: registry)
}

func shouldHandlePlanKeyboardShortcut(isInputFocused: Bool) -> Bool {
    isInputFocused
}

func canStartPlanBuild(isLoading: Bool, phase: PlanFlowPhase) -> Bool {
    !isLoading && phase != .building
}

func shouldAllowStartingPlanBuild(
    isLoadingCurrentConversation: Bool,
    phase: PlanFlowPhase,
    activeBuildPlanConversationId: UUID?,
    hasActiveBuildTask: Bool
) -> Bool {
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

func normalizedPlanStreamingSnapshot(
    _ raw: String,
    maxLength: Int = 24_000
) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    guard trimmed.count > maxLength else { return trimmed }
    return String(trimmed.suffix(maxLength))
}

func clarificationQuestionsMarkdownFromSnapshot(_ raw: String) -> String? {
    let normalized = normalizedPlanStreamingSnapshot(raw)
    guard !normalized.isEmpty else { return nil }
    guard PlanOptionsParser.parseClarificationQuestionnaire(from: normalized) != nil else {
        return nil
    }
    return normalized
}

func clarificationQuestionsMarkdownForRestore(
    _ raw: String,
    isBuildScopedConversation: Bool
) -> String? {
    guard !isBuildScopedConversation else { return nil }
    return clarificationQuestionsMarkdownFromSnapshot(raw)
}

func shouldAllowPlanToggleDeactivation(phase: PlanFlowPhase) -> Bool {
    switch phase {
    case .analyzing, .questioning, .generating, .building:
        return false
    case .idle, .proposalReady, .readyToBuild:
        return true
    }
}

func shouldDisablePlanToggleWhenPanelCloses(
    phase: PlanFlowPhase,
    planningState: PlanningState,
    coderMode: CoderMode,
    hasActiveBuildSession: Bool = false
) -> Bool {
    guard coderMode != .plan else { return false }
    guard planningState == .idle else { return false }
    if hasActiveBuildSession { return false }
    return shouldAllowPlanToggleDeactivation(phase: phase)
}

func shouldTreatConversationAsPlanContext(
    coderMode: CoderMode,
    hasInlinePlanSession: Bool,
    hasActivePlanFlowPhase: Bool,
    streamConversationId: UUID?,
    currentConversationId: UUID?,
    hasPlanBoardForStreamConversation: Bool,
    hasPlanBoardForCurrentConversation: Bool,
    showPlanPanel: Bool,
    activeBuildPlanConversationId: UUID?
) -> Bool {
    let isCurrentConversationStream: Bool = {
        guard let streamConversationId else { return true }
        guard let currentConversationId else { return false }
        return streamConversationId == currentConversationId
    }()

    if isCurrentConversationStream {
        if coderMode == .plan { return true }
        if hasInlinePlanSession { return true }
        if hasActivePlanFlowPhase { return true }
    }

    if let streamConversationId {
        // A persisted plan board alone must not force plan routing for normal
        // agent chat turns. Route only when an active plan session/build
        // is in progress.
        _ = hasPlanBoardForStreamConversation
        if streamConversationId == activeBuildPlanConversationId { return true }
        return false
    }

    if currentConversationId != nil {
        _ = hasPlanBoardForCurrentConversation
        if currentConversationId == activeBuildPlanConversationId { return true }
    }

    return false
}

func shouldRoutePlanStreamToPlanPanel(
    shouldRoutePlanStreamingToPanel: Bool,
    streamConversationId: UUID?,
    hasActivePlanContext: Bool,
    phase: PlanFlowPhase,
    activeBuildPlanConversationId: UUID?,
    activeBuildAgentConversationId: UUID?
) -> Bool {
    guard let streamConversationId else { return false }
    if hasActivePlanContext { return true }
    if phase == .building {
        if streamConversationId == activeBuildPlanConversationId { return true }
        if streamConversationId == activeBuildAgentConversationId { return true }
    }
    _ = shouldRoutePlanStreamingToPanel
    return false
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
