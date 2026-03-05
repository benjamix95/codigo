import XCTest
@testable import CoderIDE

final class PlanPanelTraceScopingTests: XCTestCase {
    func testFilterPlanTraceActivitiesForConversationKeepsOnlyMatchingConversation() {
        let targetConversationId = UUID()
        let otherConversationId = UUID()
        let matching = TaskActivity(
            type: "command_execution",
            title: "Run tests",
            payload: ["conversation_id": targetConversationId.uuidString.lowercased()],
            phase: .executing,
            isRunning: true
        )
        let other = TaskActivity(
            type: "edit",
            title: "Edit file",
            payload: ["conversation_id": otherConversationId.uuidString.lowercased()],
            phase: .editing,
            isRunning: true
        )

        let filtered = filterPlanTraceActivitiesForConversation(
            [matching, other],
            conversationId: targetConversationId
        )

        XCTAssertEqual(filtered.map(\.id), [matching.id])
    }

    func testFilterPlanTraceActivitiesForConversationReturnsAllWhenConversationIsNil() {
        let first = TaskActivity(type: "edit", title: "A", phase: .editing, isRunning: true)
        let second = TaskActivity(type: "bash", title: "B", phase: .executing, isRunning: true)

        let filtered = filterPlanTraceActivitiesForConversation([first, second], conversationId: nil)

        XCTAssertEqual(filtered.map(\.id), [first.id, second.id])
    }

    func testFilterPlanTraceActivitiesForConversationSupportsCamelCaseConversationId() {
        let targetConversationId = UUID()
        let otherConversationId = UUID()
        let matching = TaskActivity(
            type: "command_execution",
            title: "Run tests",
            payload: ["conversationId": targetConversationId.uuidString],
            phase: .executing,
            isRunning: true
        )
        let other = TaskActivity(
            type: "edit",
            title: "Edit file",
            payload: ["conversationId": otherConversationId.uuidString],
            phase: .editing,
            isRunning: true
        )

        let filtered = filterPlanTraceActivitiesForConversation(
            [matching, other],
            conversationId: targetConversationId
        )

        XCTAssertEqual(filtered.map(\.id), [matching.id])
    }
}
