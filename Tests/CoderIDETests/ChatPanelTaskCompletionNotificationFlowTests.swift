import XCTest
@testable import CoderIDE

@MainActor
final class ChatPanelTaskCompletionNotificationFlowTests: XCTestCase {
    func testSuccessOutcomeBuildsNotificationPayload() {
        let conversation = makeConversation(messages: [
            ChatMessage(role: .user, content: "Che hai fatto?"),
            ChatMessage(role: .assistant, content: "Ho completato il task.")
        ])

        let payload = buildTaskCompletionNotificationPayload(
            conversation: conversation,
            outcome: .success
        )

        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.title, "Task completato")
        XCTAssertEqual(payload?.body, "Apri CoderIDE per vedere i dettagli.")
    }

    func testFailedOrAbortedOutcomeSkipsNotificationPayload() {
        let conversation = makeConversation(messages: [
            ChatMessage(role: .user, content: "Domanda"),
            ChatMessage(role: .assistant, content: "Risposta")
        ])

        let failedPayload = buildTaskCompletionNotificationPayload(
            conversation: conversation,
            outcome: .failed
        )
        let abortedPayload = buildTaskCompletionNotificationPayload(
            conversation: conversation,
            outcome: .aborted
        )

        XCTAssertNil(failedPayload)
        XCTAssertNil(abortedPayload)
    }

    func testNilOutcomeRepresentsLingeringForceEndAndSkipsNotification() {
        let conversation = makeConversation(messages: [
            ChatMessage(role: .user, content: "Domanda"),
            ChatMessage(role: .assistant, content: "Risposta")
        ])

        let payload = buildTaskCompletionNotificationPayload(
            conversation: conversation,
            outcome: nil
        )

        XCTAssertNil(payload)
    }

    private func makeConversation(messages: [ChatMessage]) -> Conversation {
        Conversation(
            id: UUID(),
            title: "Flow Test",
            messages: messages
        )
    }
}
