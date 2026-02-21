import XCTest
@testable import CoderIDE

@MainActor
final class TaskActivityStoreSwarmCardsTests: XCTestCase {
    func testIncrementalUpdatesAcrossParallelSwarmsAndFallbackOrchestrator() {
        let store = TaskActivityStore()

        store.addActivity(
            TaskActivity(
                type: "agent",
                title: "Planner",
                detail: "started",
                payload: ["swarm_id": "planner", "group_id": "swarm-planner"],
                phase: .planning,
                isRunning: true,
                groupId: "swarm-planner"
            ))
        store.addActivity(
            TaskActivity(
                type: "agent",
                title: "Reviewer",
                detail: "started",
                payload: ["swarm_id": "reviewer", "group_id": "swarm-reviewer"],
                phase: .planning,
                isRunning: true,
                groupId: "swarm-reviewer"
            ))
        store.addActivity(
            TaskActivity(
                type: "web_search_started",
                title: "Search globale",
                detail: "started",
                payload: [:],
                phase: .searching,
                isRunning: true
            ))

        let cards = store.swarmCardStates()
        XCTAssertTrue(cards.contains(where: { $0.swarmId == "planner" }))
        XCTAssertTrue(cards.contains(where: { $0.swarmId == "reviewer" }))
        XCTAssertTrue(cards.contains(where: { $0.swarmId == "orchestrator" }))
    }

    func testAppendOrMergeBatchEventPreservesSwarmStartedAndCompleted() {
        let store = TaskActivityStore()
        let started = TaskActivity(
            type: "read_batch_started",
            title: "Read files",
            detail: "started",
            payload: ["swarm_id": "coder", "group_id": "swarm-coder", "status": "started"],
            phase: .editing,
            isRunning: true,
            groupId: "swarm-coder"
        )
        let completed = TaskActivity(
            type: "read_batch_started",
            title: "Read files",
            detail: "completed",
            payload: ["swarm_id": "coder", "group_id": "swarm-coder", "status": "completed"],
            phase: .editing,
            isRunning: false,
            groupId: "swarm-coder"
        )

        store.appendOrMergeBatchEvent(started)
        store.appendOrMergeBatchEvent(completed)

        let card = store.swarmCardStates().first(where: { $0.swarmId == "coder" })
        XCTAssertNotNil(card)
        XCTAssertGreaterThanOrEqual(card?.recentEvents.count ?? 0, 2)
    }
}
