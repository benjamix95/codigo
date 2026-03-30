import XCTest
@testable import CoderIDE

final class SubagentContextDescriptorTests: XCTestCase {
    func testCodexNativeChildThreadProducesReadOnlyThreadDescriptor() {
        let event = TaskActivity(
            type: "agent",
            title: "Explorer",
            detail: "started",
            payload: [
                "swarm_id": "sa-codex",
                "thread_id": "thread-child-42",
                "sender_thread_id": "thread-parent-9",
            ],
            timestamp: Date(timeIntervalSince1970: 300),
            phase: .executing,
            isRunning: false,
            groupId: "swarm-sa-codex"
        )
        let card = SwarmLiveCardState(
            swarmId: "sa-codex",
            taskPrompt: "Inspect project",
            recentEvents: [event]
        )

        let descriptor = SubagentContextDescriptor.from(card: card)

        XCTAssertEqual(
            descriptor,
            SubagentContextDescriptor(
                primaryLabel: "Contexto dedicato • sola lettura • Thread thread-child-42",
                secondaryLabel: "Parent thread-parent-9"
            )
        )
    }

    func testClaudeNativeTaskProducesReadOnlyTaskDescriptor() {
        let event = TaskActivity(
            type: "agent",
            title: "Reviewer",
            detail: "started",
            payload: [
                "swarm_id": "sa-claude",
                "task_id": "task_123",
            ],
            timestamp: Date(timeIntervalSince1970: 301),
            phase: .executing,
            isRunning: false,
            groupId: "swarm-sa-claude"
        )
        let card = SwarmLiveCardState(
            swarmId: "sa-claude",
            taskPrompt: "Review patch",
            recentEvents: [event]
        )

        let descriptor = SubagentContextDescriptor.from(card: card)

        XCTAssertEqual(
            descriptor,
            SubagentContextDescriptor(
                primaryLabel: "Contexto dedicato • sola lettura • Task task_123",
                secondaryLabel: nil
            )
        )
    }
}
