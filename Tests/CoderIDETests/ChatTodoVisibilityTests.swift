import XCTest
@testable import CoderIDE

final class ChatTodoVisibilityTests: XCTestCase {
    func testLiveTodoCardRemainsVisibleDuringPipelineProgress() {
        XCTAssertTrue(
            shouldShowLiveTodoCardInChat(
                hasSwarmSteps: false,
                hasLiveSwarmCards: false,
                hasPipelineProgress: true
            )
        )
    }

    func testLiveTodoCardIsHiddenWhenSwarmAlreadyOwnsProgressUI() {
        XCTAssertFalse(
            shouldShowLiveTodoCardInChat(
                hasSwarmSteps: true,
                hasLiveSwarmCards: false,
                hasPipelineProgress: false
            )
        )
        XCTAssertFalse(
            shouldShowLiveTodoCardInChat(
                hasSwarmSteps: false,
                hasLiveSwarmCards: true,
                hasPipelineProgress: false
            )
        )
    }
}
