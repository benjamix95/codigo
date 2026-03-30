import XCTest
@testable import CoderIDE

final class SwarmLiveReducerSubagentLaunchAckTests: XCTestCase {
    func testLaunchAckDoesNotCompleteCard() {
        let started = TaskActivity(
            type: "agent",
            title: "Explorer",
            detail: "started",
            payload: [
                "swarm_id": "sa-launch",
                "group_id": "swarm-sa-launch",
                "mcp_tool": "coderide_subagent_explorer",
                "status": "in_progress",
            ],
            timestamp: Date(timeIntervalSince1970: 200),
            phase: .executing,
            isRunning: false,
            groupId: "swarm-sa-launch"
        )
        let launchAck = TaskActivity(
            type: "agent",
            title: "Explorer — completed",
            detail: "completed",
            payload: [
                "swarm_id": "sa-launch",
                "group_id": "swarm-sa-launch",
                "mcp_tool": "coderide_subagent_explorer",
                "status": "completed",
                "output": "OK — subagent Explorer launched",
            ],
            timestamp: Date(timeIntervalSince1970: 201),
            phase: .executing,
            isRunning: false,
            groupId: "swarm-sa-launch"
        )

        let cards = SwarmLiveReducer.reduce(activities: [started, launchAck], limitRecentEvents: 80)

        XCTAssertEqual(cards["sa-launch"]?.status, .running)
        XCTAssertEqual(cards["sa-launch"]?.currentDetail, "Explorer • launch acknowledged")
    }

    func testRealSubagentCompletionStillCompletesCard() {
        let started = TaskActivity(
            type: "agent",
            title: "Reviewer",
            detail: "started",
            payload: [
                "swarm_id": "sa-real",
                "group_id": "swarm-sa-real",
                "mcp_tool": "coderide_subagent_reviewer",
                "status": "in_progress",
            ],
            timestamp: Date(timeIntervalSince1970: 210),
            phase: .executing,
            isRunning: false,
            groupId: "swarm-sa-real"
        )
        let completed = TaskActivity(
            type: "agent",
            title: "Reviewer — completed",
            detail: "completed",
            payload: [
                "swarm_id": "sa-real",
                "group_id": "swarm-sa-real",
                "mcp_tool": "coderide_subagent_reviewer",
                "status": "completed",
                "output": "Review completo: nessuna regressione trovata",
            ],
            timestamp: Date(timeIntervalSince1970: 211),
            phase: .executing,
            isRunning: false,
            groupId: "swarm-sa-real"
        )

        let cards = SwarmLiveReducer.reduce(activities: [started, completed], limitRecentEvents: 80)

        XCTAssertEqual(cards["sa-real"]?.status, .completed)
        XCTAssertFalse(cards["sa-real"]?.summary?.isEmpty ?? true)
        XCTAssertFalse(cards["sa-real"]?.summary?.contains("launch acknowledged") ?? false)
    }
}
