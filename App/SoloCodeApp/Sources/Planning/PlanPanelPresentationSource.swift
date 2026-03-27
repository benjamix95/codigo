import Foundation

enum PlanPanelPresentationSource: Equatable {
    case automaticFlow
    case manualShortcut
    case manualDeepLink
}

struct PlanPanelOpenState: Equatable {
    let planToggleEnabled: Bool
    let shouldResetHistorySelection: Bool
    let showPlanPanel: Bool
}

func shouldShowPlanPanelHistory(source: PlanPanelPresentationSource) -> Bool {
    source == .manualShortcut
}

func resolvePlanPanelOpenState(
    currentPlanToggleEnabled: Bool,
    preserveHistorySelection: Bool,
    source: PlanPanelPresentationSource
) -> PlanPanelOpenState {
    let shouldOpenPanel = source != .automaticFlow || currentPlanToggleEnabled
    return PlanPanelOpenState(
        planToggleEnabled: shouldOpenPanel ? true : currentPlanToggleEnabled,
        shouldResetHistorySelection: source == .automaticFlow || !preserveHistorySelection,
        showPlanPanel: shouldOpenPanel
    )
}
