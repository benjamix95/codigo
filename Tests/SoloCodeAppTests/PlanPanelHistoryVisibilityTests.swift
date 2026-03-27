import XCTest
@testable import CoderIDE

final class PlanPanelHistoryVisibilityTests: XCTestCase {
    func testHistoryVisibleOnlyForManualShortcut() {
        XCTAssertFalse(shouldShowPlanPanelHistory(source: .automaticFlow))
        XCTAssertFalse(shouldShowPlanPanelHistory(source: .manualDeepLink))
        XCTAssertTrue(shouldShowPlanPanelHistory(source: .manualShortcut))
    }

    func testAutomaticFlowOpenStateFailsClosedWithoutUserToggle() {
        let state = resolvePlanPanelOpenState(
            currentPlanToggleEnabled: false,
            preserveHistorySelection: true,
            source: .automaticFlow
        )

        XCTAssertFalse(state.planToggleEnabled)
        XCTAssertTrue(state.shouldResetHistorySelection)
        XCTAssertFalse(state.showPlanPanel)
    }

    func testAutomaticFlowOpenStateHonorsAlreadyEnabledToggle() {
        let state = resolvePlanPanelOpenState(
            currentPlanToggleEnabled: true,
            preserveHistorySelection: true,
            source: .automaticFlow
        )

        XCTAssertTrue(state.planToggleEnabled)
        XCTAssertTrue(state.shouldResetHistorySelection)
        XCTAssertTrue(state.showPlanPanel)
    }

    func testManualShortcutOpenStateCanPreserveHistory() {
        let state = resolvePlanPanelOpenState(
            currentPlanToggleEnabled: true,
            preserveHistorySelection: true,
            source: .manualShortcut
        )

        XCTAssertTrue(state.planToggleEnabled)
        XCTAssertFalse(state.shouldResetHistorySelection)
        XCTAssertTrue(state.showPlanPanel)
    }
}
