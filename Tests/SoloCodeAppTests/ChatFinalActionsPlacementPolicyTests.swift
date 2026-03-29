import XCTest
@testable import CoderIDE

final class ChatFinalActionsPlacementPolicyTests: XCTestCase {
    func testFinalActionsRenderBelowMessagesForStandardChat() {
        XCTAssertTrue(
            ChatFinalActionsPlacementPolicy.shouldRenderBelowMessages(
                shouldShowFinalChatActions: true,
                showsSwarmViewOnly: false
            )
        )
    }

    func testFinalActionsDoNotRenderBelowMessagesWhenSwarmOnly() {
        XCTAssertFalse(
            ChatFinalActionsPlacementPolicy.shouldRenderBelowMessages(
                shouldShowFinalChatActions: true,
                showsSwarmViewOnly: true
            )
        )
    }
}
