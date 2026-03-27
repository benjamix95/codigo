import XCTest
@testable import CoderIDE

final class ChatTimelineInvalidationPolicyTests: XCTestCase {
    func testTodoReadDoesNotInvalidateChatTimeline() {
        XCTAssertFalse(shouldInvalidateChatTimelineForLiveMutation(eventType: "todo_read"))
    }

    func testTodoWriteStillInvalidatesChatTimeline() {
        XCTAssertTrue(shouldInvalidateChatTimelineForLiveMutation(eventType: "todo_write"))
    }
}
