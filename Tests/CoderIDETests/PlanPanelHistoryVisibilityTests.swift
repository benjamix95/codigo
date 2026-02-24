import XCTest
@testable import CoderIDE

final class PlanPanelHistoryVisibilityTests: XCTestCase {
    func testHistoryVisibleOnlyForManualShortcut() {
        XCTAssertFalse(shouldShowPlanPanelHistory(source: .automaticFlow))
        XCTAssertFalse(shouldShowPlanPanelHistory(source: .manualDeepLink))
        XCTAssertTrue(shouldShowPlanPanelHistory(source: .manualShortcut))
    }
}
