import XCTest
@testable import CoderIDE

final class ChatPanelTaskStatusScopingTests: XCTestCase {
    func testResolveTaskStatusConversationIdPrefersPayloadConversation() {
        let payloadConversationId = UUID()
        let fallbackConversationId = UUID()

        let resolved = resolveTaskStatusConversationId(
            activityPayload: ["conversation_id": payloadConversationId.uuidString.lowercased()],
            fallbackConversationId: fallbackConversationId
        )

        XCTAssertEqual(resolved, payloadConversationId)
    }

    func testResolveTaskStatusConversationIdFallsBackWhenPayloadConversationIsMissing() {
        let fallbackConversationId = UUID()

        let resolved = resolveTaskStatusConversationId(
            activityPayload: [:],
            fallbackConversationId: fallbackConversationId
        )

        XCTAssertEqual(resolved, fallbackConversationId)
    }

    func testResolveTaskStatusConversationIdFallsBackWhenPayloadConversationIsInvalid() {
        let fallbackConversationId = UUID()

        let resolved = resolveTaskStatusConversationId(
            activityPayload: ["conversation_id": "not-a-uuid"],
            fallbackConversationId: fallbackConversationId
        )

        XCTAssertEqual(resolved, fallbackConversationId)
    }

    func testResolveTaskStatusConversationIdSupportsCamelCaseConversationKey() {
        let payloadConversationId = UUID()
        let fallbackConversationId = UUID()

        let resolved = resolveTaskStatusConversationId(
            activityPayload: ["conversationId": payloadConversationId.uuidString.lowercased()],
            fallbackConversationId: fallbackConversationId
        )

        XCTAssertEqual(resolved, payloadConversationId)
    }

    func testPayloadWithConversationScopeAddsScopeWhenMissing() {
        let conversationId = UUID()
        let payload = payloadWithConversationScope(
            payload: ["status": "running"],
            conversationId: conversationId
        )

        XCTAssertEqual(
            payload["conversation_id"],
            conversationId.uuidString.lowercased()
        )
    }

    func testPayloadWithConversationScopeRepairsEmptyConversationId() {
        let conversationId = UUID()
        let payload = payloadWithConversationScope(
            payload: ["conversation_id": "   ", "status": "done"],
            conversationId: conversationId
        )

        XCTAssertEqual(
            payload["conversation_id"],
            conversationId.uuidString.lowercased()
        )
    }

    func testPayloadWithConversationScopePreservesValidConversationId() {
        let providedConversationId = UUID()
        let payload = payloadWithConversationScope(
            payload: ["conversation_id": providedConversationId.uuidString.lowercased()],
            conversationId: UUID()
        )

        XCTAssertEqual(
            payload["conversation_id"],
            providedConversationId.uuidString.lowercased()
        )
    }

    func testPayloadWithConversationScopePromotesCamelCaseConversationKey() {
        let providedConversationId = UUID()
        let payload = payloadWithConversationScope(
            payload: ["conversationId": providedConversationId.uuidString],
            conversationId: UUID()
        )

        XCTAssertEqual(
            payload["conversation_id"],
            providedConversationId.uuidString.lowercased()
        )
    }
}
