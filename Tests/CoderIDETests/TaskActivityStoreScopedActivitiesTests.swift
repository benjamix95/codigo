import XCTest
@testable import CoderIDE

@MainActor
final class TaskActivityStoreScopedActivitiesTests: XCTestCase {
    func testActivitiesForConversationFiltersByConversationId() {
        let store = TaskActivityStore()
        let firstConversationId = UUID()
        let secondConversationId = UUID()
        store.addActivity(makeActivity(type: "command_execution", conversationId: firstConversationId))
        store.addActivity(makeActivity(type: "command_execution", conversationId: secondConversationId))
        store.flushPending()

        let scoped = store.activities(for: firstConversationId)

        XCTAssertEqual(scoped.count, 1)
        XCTAssertEqual(scoped.first?.payload["conversation_id"], firstConversationId.uuidString.lowercased())
    }

    func testPlanRelevantRecentActivitiesForConversationIsScoped() {
        let store = TaskActivityStore()
        let firstConversationId = UUID()
        let secondConversationId = UUID()
        store.addActivity(makeActivity(type: "plan_step_upsert", conversationId: firstConversationId))
        store.addActivity(makeActivity(type: "plan_step_upsert", conversationId: secondConversationId))
        store.flushPending()

        let scoped = store.planRelevantRecentActivities(limit: 20, conversationId: firstConversationId)

        XCTAssertEqual(scoped.count, 1)
        XCTAssertEqual(scoped.first?.payload["conversation_id"], firstConversationId.uuidString.lowercased())
    }

    private func makeActivity(type: String, conversationId: UUID) -> TaskActivity {
        TaskActivity(
            type: type,
            title: type,
            detail: nil,
            payload: ["conversation_id": conversationId.uuidString.lowercased()],
            timestamp: Date(),
            phase: .planning,
            isRunning: false
        )
    }
}
