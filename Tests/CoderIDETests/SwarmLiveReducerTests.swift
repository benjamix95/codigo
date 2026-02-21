import XCTest
@testable import CoderIDE

final class SwarmLiveReducerTests: XCTestCase {
    func testAgentStartedCreatesRunningCard() {
        let activity = TaskActivity(
            type: "agent",
            title: "Planner",
            detail: "started",
            payload: ["swarm_id": "planner", "group_id": "swarm-planner"],
            timestamp: Date(timeIntervalSince1970: 100),
            phase: .planning,
            isRunning: true,
            groupId: "swarm-planner"
        )
        let cards = SwarmLiveReducer.reduce(activities: [activity], limitRecentEvents: 80)
        XCTAssertEqual(cards["planner"]?.status, .running)
        XCTAssertEqual(cards["planner"]?.currentStepTitle, "Planner")
    }

    func testAgentCompletedAutoCollapsesAndSetsSummary() {
        let started = TaskActivity(
            type: "agent",
            title: "Coder",
            detail: "started",
            payload: ["swarm_id": "coder", "group_id": "swarm-coder"],
            timestamp: Date(timeIntervalSince1970: 100),
            phase: .planning,
            isRunning: true,
            groupId: "swarm-coder"
        )
        let completed = TaskActivity(
            type: "agent",
            title: "Coder",
            detail: "completed",
            payload: ["swarm_id": "coder", "group_id": "swarm-coder"],
            timestamp: Date(timeIntervalSince1970: 105),
            phase: .planning,
            isRunning: false,
            groupId: "swarm-coder"
        )
        let cards = SwarmLiveReducer.reduce(activities: [started, completed], limitRecentEvents: 80)
        let card = cards["coder"]
        XCTAssertEqual(card?.status, .completed)
        XCTAssertTrue(card?.isCollapsed == true)
        XCTAssertNotNil(card?.summary)
    }

    func testErrorEventSetsFailedStatus() {
        let failed = TaskActivity(
            type: "tool_execution_error",
            title: "Errore tool",
            detail: "failed",
            payload: ["swarm_id": "debugger", "group_id": "swarm-debugger"],
            timestamp: Date(timeIntervalSince1970: 120),
            phase: .executing,
            isRunning: false,
            groupId: "swarm-debugger"
        )
        let cards = SwarmLiveReducer.reduce(activities: [failed], limitRecentEvents: 80)
        XCTAssertEqual(cards["debugger"]?.status, .failed)
        XCTAssertFalse(cards["debugger"]?.isCollapsed ?? true)
    }

    func testGroupIdFallbackMapsEventToSwarmWithoutSwarmId() {
        let activity = TaskActivity(
            type: "read_batch_started",
            title: "Read batch",
            detail: "started",
            payload: ["group_id": "swarm-reviewer"],
            timestamp: Date(timeIntervalSince1970: 130),
            phase: .editing,
            isRunning: true,
            groupId: "swarm-reviewer"
        )
        let cards = SwarmLiveReducer.reduce(activities: [activity], limitRecentEvents: 80)
        XCTAssertNotNil(cards["reviewer"])
    }

    func testDedupByStableKeyPreventsDuplicateRecentEvents() {
        let ts = Date(timeIntervalSince1970: 200)
        let a = TaskActivity(
            type: "agent",
            title: "Planner",
            detail: "started",
            payload: ["swarm_id": "planner", "status": "started", "group_id": "swarm-planner"],
            timestamp: ts,
            phase: .planning,
            isRunning: true,
            groupId: "swarm-planner"
        )
        let b = TaskActivity(
            type: "agent",
            title: "Planner",
            detail: "started",
            payload: ["swarm_id": "planner", "status": "started", "group_id": "swarm-planner"],
            timestamp: ts,
            phase: .planning,
            isRunning: true,
            groupId: "swarm-planner"
        )
        let cards = SwarmLiveReducer.reduce(activities: [a, b], limitRecentEvents: 80)
        XCTAssertEqual(cards["planner"]?.recentEvents.count, 1)
    }
}
