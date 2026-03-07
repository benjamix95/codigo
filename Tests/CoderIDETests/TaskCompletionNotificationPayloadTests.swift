import XCTest
@testable import CoderIDE

@MainActor
final class TaskCompletionNotificationPayloadTests: XCTestCase {
    func testBuildUsesPrivacyPreservingNotificationText() {
        let conversation = makeConversation(messages: [
            ChatMessage(role: .user, content: "Prima domanda"),
            ChatMessage(role: .assistant, content: "Prima risposta"),
            ChatMessage(role: .user, content: "Domanda finale"),
            ChatMessage(role: .assistant, content: "Risposta finale")
        ])

        let payload = TaskCompletionNotificationPayload.build(from: conversation)

        XCTAssertEqual(payload?.title, "Task completato")
        XCTAssertEqual(payload?.body, "Apri CoderIDE per vedere i dettagli.")
    }

    func testBuildStillResolvesLastFinalAssistantMessage() {
        let conversation = makeConversation(messages: [
            ChatMessage(role: .user, content: "Q"),
            ChatMessage(role: .assistant, content: "Parziale", isStreaming: true),
            ChatMessage(role: .assistant, content: "   "),
            ChatMessage(role: .assistant, content: "Risultato finale")
        ])

        let payload = TaskCompletionNotificationPayload.build(from: conversation)

        XCTAssertEqual(payload?.title, "Task completato")
        XCTAssertEqual(payload?.body, "Apri CoderIDE per vedere i dettagli.")
    }

    func testBuildUsesPrivacyTextWithoutUserQuestion() {
        let conversation = makeConversation(messages: [
            ChatMessage(role: .assistant, content: "Solo output finale")
        ])

        let payload = TaskCompletionNotificationPayload.build(from: conversation)

        XCTAssertEqual(payload?.title, "Task completato")
        XCTAssertEqual(payload?.body, "Apri CoderIDE per vedere i dettagli.")
    }

    func testBuildReturnsNilWhenAssistantAnswerIsMissingOrSanitizedToEmpty() {
        let conversation = makeConversation(messages: [
            ChatMessage(role: .user, content: "Domanda"),
            ChatMessage(role: .assistant, content: "[CODERIDE:todo_write|id=t1|title=Task|status=done]")
        ])

        let payload = TaskCompletionNotificationPayload.build(from: conversation)

        XCTAssertNil(payload)
    }

    func testBuildUsesConfiguredPrivacyText() {
        let conversation = makeConversation(messages: [
            ChatMessage(role: .user, content: "Domanda"),
            ChatMessage(role: .assistant, content: "Risposta")
        ])
        let formatter = TaskCompletionNotificationFormatter(
            titleMaxChars: 4,
            bodyMaxChars: 5,
            fallbackTitle: "Completato",
            fallbackBody: "Apri per i dettagli",
            ellipsis: "…"
        )

        let payload = TaskCompletionNotificationPayload.build(from: conversation, formatter: formatter)

        XCTAssertEqual(payload?.title, "Com…")
        XCTAssertEqual(payload?.body, "Apri…")
    }

    func testBuildSanitizesMessagesBeforeEmittingPrivacyText() {
        let conversation = makeConversation(messages: [
            ChatMessage(role: .user, content: "   Quale   domanda?  \n\n"),
            ChatMessage(role: .assistant, content: "Riga 1\n\n\nRiga   2   con   spazi")
        ])

        let payload = TaskCompletionNotificationPayload.build(from: conversation)

        XCTAssertEqual(payload?.title, "Task completato")
        XCTAssertEqual(payload?.body, "Apri CoderIDE per vedere i dettagli.")
    }

    private func makeConversation(messages: [ChatMessage]) -> Conversation {
        Conversation(
            id: UUID(),
            title: "Test",
            messages: messages
        )
    }
}
