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
}
