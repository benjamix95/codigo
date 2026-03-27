import XCTest
@testable import CoderIDE

final class DebugUserOptInPolicyTests: XCTestCase {
    func testResolvedModeForConversationDemotesDebugWhenToggleIsOff() {
        XCTAssertEqual(
            resolvedModeForConversation(
                requestedMode: .debug,
                debugToggleEnabled: false
            ),
            .agent
        )
        XCTAssertEqual(
            resolvedModeForConversation(
                requestedMode: .debug,
                debugToggleEnabled: true
            ),
            .debug
        )
    }

    func testShouldUseDebugUXContextRequiresUserOptIn() {
        XCTAssertFalse(
            shouldUseDebugUXContext(
                coderMode: .debug,
                showDebugPanel: true,
                debugToggleEnabled: false
            )
        )
        XCTAssertTrue(
            shouldUseDebugUXContext(
                coderMode: .debug,
                showDebugPanel: true,
                debugToggleEnabled: true
            )
        )
    }

    func testShouldRouteDebugProjectionEventRequiresToggle() {
        let event = NormalizedEvent.activateDebugMode(reason: "Investigate crash")
        XCTAssertFalse(shouldRouteDebugProjectionEvent(event, debugToggleEnabled: false))
        XCTAssertTrue(shouldRouteDebugProjectionEvent(event, debugToggleEnabled: true))
    }

    func testShouldDisplayTaskActivityHidesDebugActivitiesWithoutOptIn() {
        XCTAssertFalse(shouldDisplayTaskActivity(type: "debug_phase_update", debugToggleEnabled: false))
        XCTAssertFalse(shouldDisplayTaskActivity(type: "activate_debug_mode", debugToggleEnabled: false))
        XCTAssertTrue(shouldDisplayTaskActivity(type: "todo_write", debugToggleEnabled: false))
        XCTAssertTrue(shouldDisplayTaskActivity(type: "debug_phase_update", debugToggleEnabled: true))
    }
}
