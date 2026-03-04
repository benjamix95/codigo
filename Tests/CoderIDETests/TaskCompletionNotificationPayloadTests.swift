import XCTest
@testable import CoderIDE

@MainActor
final class TaskCompletionNotificationPayloadTests: XCTestCase {
    func testBuildExtractsLastUserQuestionAndFinalAssistantAnswer() {
        let conversation = makeConversation(messages: [
            ChatMessage(role: .user, content: "Prima domanda"),
            ChatMessage(role: .assistant, content: "Prima risposta"),
            ChatMessage(role: .user, content: "Domanda finale"),
            ChatMessage(role: .assistant, content: "Risposta finale")
        ])

        let payload = TaskCompletionNotificationPayload.build(from: conversation)

        XCTAssertEqual(payload?.title, "Domanda finale")
        XCTAssertEqual(payload?.body, "Risposta finale")
    }

    func testBuildIgnoresStreamingOrEmptyAssistantMessages() {
        let conversation = makeConversation(messages: [
            ChatMessage(role: .user, content: "Q"),
            ChatMessage(role: .assistant, content: "Parziale", isStreaming: true),
            ChatMessage(role: .assistant, content: "   "),
            ChatMessage(role: .assistant, content: "Risultato finale")
        ])

        let payload = TaskCompletionNotificationPayload.build(from: conversation)

        XCTAssertEqual(payload?.title, "Q")
        XCTAssertEqual(payload?.body, "Risultato finale")
    }

    func testBuildFallsBackToDefaultTitleWhenNoUserQuestionExists() {
        let conversation = makeConversation(messages: [
            ChatMessage(role: .assistant, content: "Solo output finale")
        ])

        let payload = TaskCompletionNotificationPayload.build(from: conversation)

        XCTAssertEqual(payload?.title, "Task completato")
        XCTAssertEqual(payload?.body, "Solo output finale")
    }

    func testBuildReturnsNilWhenAssistantAnswerIsMissingOrSanitizedToEmpty() {
        let conversation = makeConversation(messages: [
            ChatMessage(role: .user, content: "Domanda"),
            ChatMessage(role: .assistant, content: "[CODERIDE:todo_write|id=t1|title=Task|status=done]")
        ])

        let payload = TaskCompletionNotificationPayload.build(from: conversation)

        XCTAssertNil(payload)
    }

    func testBuildAppliesConfiguredTruncationLimits() {
        let longQuestion = String(repeating: "Q", count: 200)
        let longAnswer = String(repeating: "A", count: 400)
        let conversation = makeConversation(messages: [
            ChatMessage(role: .user, content: longQuestion),
            ChatMessage(role: .assistant, content: longAnswer)
        ])

        let payload = TaskCompletionNotificationPayload.build(from: conversation)

        XCTAssertEqual(payload?.title.count, 120)
        XCTAssertEqual(payload?.body.count, 240)
        XCTAssertTrue(payload?.title.hasSuffix("…") == true)
        XCTAssertTrue(payload?.body.hasSuffix("…") == true)
    }

    func testBuildSanitizesWhitespaceAndCollapsesNewlines() {
        let conversation = makeConversation(messages: [
            ChatMessage(role: .user, content: "   Quale   domanda?  \n\n"),
            ChatMessage(role: .assistant, content: "Riga 1\n\n\nRiga   2   con   spazi")
        ])

        let payload = TaskCompletionNotificationPayload.build(from: conversation)

        XCTAssertEqual(payload?.title, "Quale domanda?")
        XCTAssertEqual(payload?.body, "Riga 1\nRiga 2 con spazi")
    }

    private func makeConversation(messages: [ChatMessage]) -> Conversation {
        Conversation(
            id: UUID(),
            title: "Test",
            messages: messages
        )
    }
}
