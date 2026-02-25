import XCTest
@testable import CoderIDE

final class MessageRowCopyEligibilityTests: XCTestCase {
    func testUserMessageIsCopyableWhenNotEmpty() {
        let message = ChatMessage(role: .user, content: "Hello", isStreaming: false)
        XCTAssertTrue(MessageRow.shouldShowCopyAction(for: message))
    }

    func testUserMessageIsNotCopyableWhenEmpty() {
        let message = ChatMessage(role: .user, content: "   \n  ", isStreaming: false)
        XCTAssertFalse(MessageRow.shouldShowCopyAction(for: message))
    }

    func testAssistantMessageIsCopyableWhenFinal() {
        let message = ChatMessage(role: .assistant, content: "Final answer", isStreaming: false)
        XCTAssertTrue(MessageRow.shouldShowCopyAction(for: message))
    }

    func testAssistantMessageIsNotCopyableWhileStreaming() {
        let message = ChatMessage(role: .assistant, content: "Working...", isStreaming: true)
        XCTAssertFalse(MessageRow.shouldShowCopyAction(for: message))
    }
}
