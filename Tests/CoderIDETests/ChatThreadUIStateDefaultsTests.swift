import XCTest
@testable import CoderIDE

final class ChatThreadUIStateDefaultsTests: XCTestCase {
    func testStartsNewThreadWithCleanUIStateWhenNoSnapshotAndNoUserMessages() {
        XCTAssertTrue(
            shouldStartThreadWithCleanUIState(
                hasPersistedUIState: false,
                hasUserMessages: false
            )
        )
    }

    func testKeepsContextualDefaultsWhenThreadAlreadyHasUserMessages() {
        XCTAssertFalse(
            shouldStartThreadWithCleanUIState(
                hasPersistedUIState: false,
                hasUserMessages: true
            )
        )
    }

    func testRestoresPersistedSnapshotEvenIfThreadHasNoUserMessages() {
        XCTAssertFalse(
            shouldStartThreadWithCleanUIState(
                hasPersistedUIState: true,
                hasUserMessages: false
            )
        )
    }
}
