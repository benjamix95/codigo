import XCTest
@testable import CoderIDE

final class ChatPanelTraceBindingTests: XCTestCase {
    func testResolverUsesActiveTurnWhenConversationMatches() {
        let conversationId = UUID()
        let active = ToolTraceBindingTarget(
            conversationId: conversationId,
            assistantMessageId: UUID()
        )

        let target = ToolTraceBindingResolver.resolve(
            activeTurn: active,
            requestedConversationId: conversationId,
            fallbackAssistantMessageId: UUID()
        )

        XCTAssertEqual(target, active)
    }

    func testResolverFallsBackToLastAssistantMessageWhenNoActiveTurn() {
        let conversationId = UUID()
        let assistantMessageId = UUID()

        let target = ToolTraceBindingResolver.resolve(
            activeTurn: nil,
            requestedConversationId: conversationId,
            fallbackAssistantMessageId: assistantMessageId
        )

        XCTAssertEqual(
            target,
            ToolTraceBindingTarget(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId
            )
        )
    }

    func testResolverReturnsNilWithoutConversationOrAssistant() {
        XCTAssertNil(ToolTraceBindingResolver.resolve(
            activeTurn: nil,
            requestedConversationId: nil,
            fallbackAssistantMessageId: UUID()
        ))
        XCTAssertNil(ToolTraceBindingResolver.resolve(
            activeTurn: nil,
            requestedConversationId: UUID(),
            fallbackAssistantMessageId: nil
        ))
    }

    func testFallbackStreamingAssistantMessageIdIgnoresCompletedAssistantMessages() {
        let conversation = Conversation(
            id: UUID(),
            title: "Trace",
            messages: [
                ChatMessage(role: .assistant, content: "done", isStreaming: false),
                ChatMessage(role: .assistant, content: "still running", isStreaming: true),
            ]
        )

        XCTAssertEqual(
            fallbackStreamingAssistantMessageId(in: conversation),
            conversation.messages.last?.id
        )
    }

    func testResolvePipelineBindingTargetReturnsNilWithoutActiveTurnOrStreamingAssistant() {
        let conversation = Conversation(
            id: UUID(),
            title: "Trace",
            messages: [
                ChatMessage(role: .assistant, content: "summary", isStreaming: false)
            ]
        )

        XCTAssertNil(resolvePipelineBindingTarget(conversation: conversation, activeTurn: nil))
    }

    func testResolvePipelineBindingTargetPrefersActiveTurnOverLastStreamingAssistant() {
        let boundMessageId = UUID()
        let streamingMessageId = UUID()
        let conversation = Conversation(
            id: UUID(),
            title: "Trace",
            messages: [
                ChatMessage(id: boundMessageId, role: .assistant, content: "bound", isStreaming: false),
                ChatMessage(id: streamingMessageId, role: .assistant, content: "streaming", isStreaming: true),
            ]
        )
        let activeTurn = ToolTraceTurnContext(
            conversationId: conversation.id,
            assistantMessageId: boundMessageId,
            providerId: "codex"
        )

        let target = resolvePipelineBindingTarget(
            conversation: conversation,
            activeTurn: activeTurn
        )

        XCTAssertEqual(target?.messageId, boundMessageId)
    }

    func testResolvePipelineBindingTargetDoesNotFallbackWhenActiveTurnMessageIsMissing() {
        let streamingMessageId = UUID()
        let conversation = Conversation(
            id: UUID(),
            title: "Trace",
            messages: [
                ChatMessage(id: streamingMessageId, role: .assistant, content: "streaming", isStreaming: true)
            ]
        )
        let activeTurn = ToolTraceTurnContext(
            conversationId: conversation.id,
            assistantMessageId: UUID(),
            providerId: "codex"
        )

        XCTAssertNil(resolvePipelineBindingTarget(conversation: conversation, activeTurn: activeTurn))
    }
}
