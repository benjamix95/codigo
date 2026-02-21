import XCTest
@testable import CoderIDE

final class SwarmLiveBoardStateTests: XCTestCase {
    func testSortingRunningFailedCompleted() {
        let now = Date()
        let states: [SwarmLiveCardState] = [
            SwarmLiveCardState(
                swarmId: "completed",
                status: .completed,
                lastEventAt: now.addingTimeInterval(-20)
            ),
            SwarmLiveCardState(
                swarmId: "failed",
                status: .failed,
                lastEventAt: now.addingTimeInterval(-10)
            ),
            SwarmLiveCardState(
                swarmId: "running",
                status: .running,
                lastEventAt: now
            ),
        ]
        let sorted = SwarmLiveReducer.sorted(states: states)
        XCTAssertEqual(sorted.map(\.swarmId), ["running", "failed", "completed"])
    }

    func testCollapsedCardReceivesUnreadOnNewEvent() {
        var cards: [String: SwarmLiveCardState] = [
            "coder": SwarmLiveCardState(
                swarmId: "coder",
                status: .completed,
                startedAt: Date(timeIntervalSince1970: 100),
                lastEventAt: Date(timeIntervalSince1970: 110),
                completedAt: Date(timeIntervalSince1970: 110),
                currentStepTitle: "Done",
                currentDetail: "",
                activeOpsCount: 0,
                errorCount: 0,
                recentEvents: [],
                summary: "ok",
                isCollapsed: true,
                hasUnreadSinceCollapse: false
            )
        ]
        var dedupe: [String: Set<String>] = [:]
        let activity = TaskActivity(
            type: "mcp_tool_call",
            title: "Nuova attività",
            detail: "running",
            payload: ["swarm_id": "coder", "group_id": "swarm-coder", "status": "started"],
            phase: .executing,
            isRunning: true,
            groupId: "swarm-coder"
        )
        SwarmLiveReducer.apply(
            activity: activity,
            to: &cards,
            dedupeKeys: &dedupe,
            limitRecentEvents: 80
        )
        XCTAssertTrue(cards["coder"]?.hasUnreadSinceCollapse ?? false)
    }

    func testRecentEventsCappedToLimit() {
        var activities: [TaskActivity] = []
        for idx in 0..<120 {
            activities.append(
                TaskActivity(
                    type: "agent",
                    title: "Event \(idx)",
                    detail: "started",
                    payload: [
                        "swarm_id": "planner",
                        "group_id": "swarm-planner",
                        "status": "started",
                    ],
                    timestamp: Date(timeIntervalSince1970: TimeInterval(idx)),
                    phase: .planning,
                    isRunning: true,
                    groupId: "swarm-planner"
                ))
        }
        let cards = SwarmLiveReducer.reduce(activities: activities, limitRecentEvents: 80)
        XCTAssertEqual(cards["planner"]?.recentEvents.count, 80)
    }
}
