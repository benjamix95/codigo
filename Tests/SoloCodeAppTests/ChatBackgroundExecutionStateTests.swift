import XCTest
@testable import CoderIDE

final class ChatBackgroundExecutionStateTests: XCTestCase {
    func testShouldRecordFallbackTurnStartEventUsesScopedActivityCount() {
        XCTAssertTrue(
            shouldRecordFallbackTurnStartEvent(
                isTaskActive: true,
                scopedActivityCount: 0
            )
        )
        XCTAssertFalse(
            shouldRecordFallbackTurnStartEvent(
                isTaskActive: true,
                scopedActivityCount: 1
            )
        )
        XCTAssertFalse(
            shouldRecordFallbackTurnStartEvent(
                isTaskActive: false,
                scopedActivityCount: 0
            )
        )
    }

    func testShouldClearThreadScopedSwarmStateAfterConversationSwitchOnlyWhenInactive() {
        XCTAssertFalse(
            shouldClearThreadScopedSwarmStateAfterConversationSwitch(
                isTaskActiveForOldConversation: true
            )
        )
        XCTAssertTrue(
            shouldClearThreadScopedSwarmStateAfterConversationSwitch(
                isTaskActiveForOldConversation: false
            )
        )
    }
}
