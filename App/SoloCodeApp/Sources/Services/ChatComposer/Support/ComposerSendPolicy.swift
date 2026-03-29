import Foundation

enum ComposerSendDispatchRoute: Equatable {
    case fastModeToggle
    case standardSend
    case interruptAndSendFollowUp
}

func resolveComposerSendDispatchRoute(
    trimmedInput: String,
    selectedProviderId: String?,
    isLoadingCurrentConversation: Bool
) -> ComposerSendDispatchRoute {
    if trimmedInput.lowercased() == "/fast", selectedProviderId == "codex-cli" {
        return .fastModeToggle
    }
    if isLoadingCurrentConversation {
        return .interruptAndSendFollowUp
    }
    return .standardSend
}

func shouldSubmitComposerDraft(
    hasDraftContent: Bool,
    planningState: PlanningState
) -> Bool {
    guard hasDraftContent else { return false }
    if case .awaitingChoice = planningState {
        return false
    }
    return true
}

func canComposerDispatchMessage(
    isProjectContextAvailable: Bool,
    hasDraftContent: Bool,
    planningState: PlanningState
) -> Bool {
    guard isProjectContextAvailable else { return false }
    return shouldSubmitComposerDraft(
        hasDraftContent: hasDraftContent,
        planningState: planningState
    )
}
