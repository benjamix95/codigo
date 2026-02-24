import Foundation

enum PlanPanelPresentationSource: Equatable {
    case automaticFlow
    case manualShortcut
    case manualDeepLink
}

func shouldShowPlanPanelHistory(source: PlanPanelPresentationSource) -> Bool {
    source == .manualShortcut
}
