import XCTest
@testable import CoderIDE

@MainActor
final class TaskActivityPanelScopingTests: XCTestCase {
    func testPlanSignalsAreScopedToPanelConversation() {
        let targetConversationId = UUID()
        let otherConversationId = UUID()
        let store = TaskActivityStore()
        store.addActivity(makePlanActivity(type: "plan_step_upsert", status: "running", conversationId: otherConversationId))
        store.flushPending()

        let panel = makePanel(conversationId: targetConversationId, taskActivityStore: store)

        XCTAssertFalse(panel.hasPlanProgressSignal)
        XCTAssertFalse(panel.hasPlanExecutionSignal)
    }

    func testPlanSignalsIncludeRunningStepForMatchingConversation() {
        let targetConversationId = UUID()
        let store = TaskActivityStore()
        store.addActivity(makePlanActivity(type: "plan_step_upsert", status: "running", conversationId: targetConversationId))
        store.flushPending()

        let panel = makePanel(conversationId: targetConversationId, taskActivityStore: store)

        XCTAssertTrue(panel.hasPlanProgressSignal)
        XCTAssertTrue(panel.hasPlanExecutionSignal)
    }

    private func makePanel(
        conversationId: UUID?,
        taskActivityStore: TaskActivityStore
    ) -> TaskActivityPanel {
        TaskActivityPanel(
            chatStore: ChatStore(),
            taskActivityStore: taskActivityStore,
            todoStore: TodoStore(),
            conversationId: conversationId,
            coderMode: .plan,
            debugPhase: .idle,
            onOpenFile: { _ in },
            effectivePrimaryPath: nil,
            showTodoSection: true
        )
    }

    private func makePlanActivity(
        type: String,
        status: String,
        conversationId: UUID
    ) -> TaskActivity {
        TaskActivity(
            type: type,
            title: type,
            payload: [
                "status": status,
                "conversation_id": conversationId.uuidString.lowercased(),
            ],
            phase: .planning,
            isRunning: status == "running"
        )
    }
}
