import XCTest
@testable import CoderIDE

final class ChatAutoScrollFollowPolicyTests: XCTestCase {
    func testPolicyKeepsFollowLiveWhenViewportReturnsNearBottom() {
        let result = ChatAutoScrollFollowPolicy.updatedIsFollowingLive(
            currentValue: false,
            isNearBottom: true,
            isConversationBusy: true,
            secondsSinceProgrammaticScroll: 1
        )

        XCTAssertTrue(result)
    }

    func testPolicyDetachesFollowLiveWhenUserMovesAwayFromBottomDuringBusyTask() {
        let result = ChatAutoScrollFollowPolicy.updatedIsFollowingLive(
            currentValue: true,
            isNearBottom: false,
            isConversationBusy: true,
            secondsSinceProgrammaticScroll: 1
        )

        XCTAssertFalse(result)
    }

    func testPolicyIgnoresRecentProgrammaticScrollViewportJitter() {
        let result = ChatAutoScrollFollowPolicy.updatedIsFollowingLive(
            currentValue: true,
            isNearBottom: false,
            isConversationBusy: true,
            secondsSinceProgrammaticScroll: 0.01
        )

        XCTAssertTrue(result)
    }
}
