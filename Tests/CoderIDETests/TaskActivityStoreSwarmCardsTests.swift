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

    func testSwarmIdsAndLaneFilteringUseGroupIdFallback() {
        let store = TaskActivityStore()

        store.addActivity(
            TaskActivity(
                type: "read_batch_started",
                title: "Group only read",
                detail: "started",
                payload: ["group_id": "swarm-reviewer"],
                phase: .editing,
                isRunning: true
            ))

        XCTAssertEqual(store.swarmIds(), ["reviewer"])
        XCTAssertEqual(store.activities(forSwarmId: "reviewer").count, 1)

        let reviewerLane = store.activitiesForSwarmLane("reviewer")
        XCTAssertEqual(reviewerLane.count, 1)
        XCTAssertEqual(reviewerLane.first?.payload["group_id"], "swarm-reviewer")
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
        store.flushPending()

        let card = store.swarmCardStates().first(where: { $0.swarmId == "coder" })
        XCTAssertNotNil(card)
        XCTAssertGreaterThanOrEqual(card?.recentEvents.count ?? 0, 2)
    }

    func testAppendOrMergeBatchEventHardCapPreservesRunningActivities() {
        let store = TaskActivityStore()
        let running = TaskActivity(
            type: "agent",
            title: "Long running operation",
            detail: "running",
            payload: ["status": "running"],
            phase: .planning,
            isRunning: true,
            groupId: "running-anchor"
        )
        store.appendOrMergeBatchEvent(running)

        for index in 0...store.activitiesHardCap {
            store.appendOrMergeBatchEvent(
                TaskActivity(
                    type: "batch_log",
                    title: "Log \(index)",
                    detail: "completed",
                    payload: ["status": "completed"],
                    phase: .planning,
                    isRunning: false,
                    groupId: "batch-\(index)"
                )
            )
        }

        XCTAssertEqual(store.activities.count, store.activitiesHardCap)
        XCTAssertTrue(store.activities.contains(where: { $0.id == running.id }))
    }
}
