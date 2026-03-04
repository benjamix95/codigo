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
}
