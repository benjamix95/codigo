import XCTest
@testable import CoderIDE

final class ChatPanelAutoTodoTracePayloadTests: XCTestCase {
    func testBuildAutoTodoTracePayloadIncludesConversationScopeWhenProvided() {
        let conversationId = UUID()
        let payload = buildAutoTodoTracePayload(
            todoId: UUID(),
            title: "Fix TODO scope",
            status: .done,
            notes: "Completed",
            linkedFiles: ["Sources/File.swift"],
            conversationId: conversationId
        )

        XCTAssertEqual(
            payload["conversation_id"],
            conversationId.uuidString.lowercased()
        )
    }

    func testBuildAutoTodoTracePayloadOmitsConversationScopeWhenMissing() {
        let payload = buildAutoTodoTracePayload(
            todoId: UUID(),
            title: "Fix TODO scope",
            status: .blocked,
            notes: "Blocked",
            linkedFiles: [],
            conversationId: nil
        )

        XCTAssertNil(payload["conversation_id"])
    }
}
