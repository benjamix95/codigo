import SwiftUI

private struct PlanPanelSuppressCanonicalTodoSummaryCardKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// When true, `PlanPanelView` omits `TodoSummaryCardView` in the scroll area because the composer overlay already lists the same todos.
    var planPanelSuppressCanonicalTodoSummaryCard: Bool {
        get { self[PlanPanelSuppressCanonicalTodoSummaryCardKey.self] }
        set { self[PlanPanelSuppressCanonicalTodoSummaryCardKey.self] = newValue }
    }
}
