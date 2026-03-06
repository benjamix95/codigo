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

    func testCompletedDetailOverridesIsRunningFlag() {
        let completedButRunning = TaskActivity(
            type: "agent",
            title: "Reviewer",
            detail: "completed",
            payload: [
                "swarm_id": "reviewer",
                "group_id": "swarm-reviewer",
                "status": "completed",
            ],
            timestamp: Date(timeIntervalSince1970: 106),
            phase: .executing,
            isRunning: true, // Some providers may leak a stale running flag.
            groupId: "swarm-reviewer"
        )
        let cards = SwarmLiveReducer.reduce(activities: [completedButRunning], limitRecentEvents: 80)
        XCTAssertEqual(cards["reviewer"]?.status, .completed)
    }

    func testErrorEventSetsFailedStatus() {
        let failed = TaskActivity(
            type: "tool_execution_error",
            title: "Tool error",
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

    func testCamelCaseSwarmIdMapsEventToSwarm() {
        let activity = TaskActivity(
            type: "mcp_tool_call",
            title: "MCP invoke swarm",
            detail: "completed",
            payload: ["swarmId": "invoke-call-7", "status": "completed"],
            timestamp: Date(timeIntervalSince1970: 132),
            phase: .executing,
            isRunning: false,
            groupId: nil
        )
        let cards = SwarmLiveReducer.reduce(activities: [activity], limitRecentEvents: 80)
        XCTAssertNotNil(cards["invoke-call-7"])
    }

    func testCamelCaseGroupIdFallbackMapsEventToSwarm() {
        let activity = TaskActivity(
            type: "mcp_tool_call",
            title: "MCP invoke swarm",
            detail: "started",
            payload: ["groupId": "swarm-reviewer", "status": "started"],
            timestamp: Date(timeIntervalSince1970: 133),
            phase: .executing,
            isRunning: true,
            groupId: nil
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

    func testQueuedSwarmIdPrefixIsFiltered() {
        let activity = TaskActivity(
            type: "agent",
            title: "Explorer",
            detail: "queued",
            payload: ["swarm_id": "queued-tc123", "status": "queued"],
            timestamp: Date(timeIntervalSince1970: 300),
            phase: .planning,
            isRunning: false,
            groupId: nil
        )
        let cards = SwarmLiveReducer.reduce(activities: [activity], limitRecentEvents: 80)
        XCTAssertNil(cards["queued-tc123"], "Queued placeholder cards should be filtered out")
    }

    func testAgentNamePayloadPersistsAsDisplayName() {
        let started = TaskActivity(
            type: "agent",
            title: "Explorer",
            detail: "Investigate auth refresh flow",
            payload: [
                "swarm_id": "InvestigateAuthRefresh-explorer",
                "group_id": "swarm-InvestigateAuthRefresh-explorer",
                "agent_name": "InvestigateAuthRefresh-explorer",
                "status": "started",
            ],
            timestamp: Date(timeIntervalSince1970: 301),
            phase: .planning,
            isRunning: true,
            groupId: "swarm-InvestigateAuthRefresh-explorer"
        )
        let toolEvent = TaskActivity(
            type: "read_batch_started",
            title: "Read session manager",
            detail: "/Sources/Auth/SessionManager.swift",
            payload: [
                "swarm_id": "InvestigateAuthRefresh-explorer",
                "group_id": "swarm-InvestigateAuthRefresh-explorer",
                "status": "started",
            ],
            timestamp: Date(timeIntervalSince1970: 302),
            phase: .searching,
            isRunning: true,
            groupId: "swarm-InvestigateAuthRefresh-explorer"
        )

        let cards = SwarmLiveReducer.reduce(
            activities: [started, toolEvent],
            limitRecentEvents: 80
        )
        XCTAssertEqual(
            cards["InvestigateAuthRefresh-explorer"]?.displayName,
            "InvestigateAuthRefresh-explorer"
        )
    }

    func testActiveOpsCountDecrementsOnNonRunningEvent() {
        let started = TaskActivity(
            type: "agent",
            title: "Coder",
            detail: "started",
            payload: ["swarm_id": "coder", "group_id": "swarm-coder", "status": "started"],
            timestamp: Date(timeIntervalSince1970: 100),
            phase: .executing,
            isRunning: true,
            groupId: "swarm-coder"
        )
        let step = TaskActivity(
            type: "read_batch_completed",
            title: "Read files",
            detail: "done",
            payload: ["swarm_id": "coder", "group_id": "swarm-coder", "status": "ok"],
            timestamp: Date(timeIntervalSince1970: 101),
            phase: .executing,
            isRunning: false,
            groupId: "swarm-coder"
        )
        let cards = SwarmLiveReducer.reduce(activities: [started, step], limitRecentEvents: 80)
        XCTAssertEqual(cards["coder"]?.activeOpsCount, 0)
    }

    func testDedupWithFinerGranularity() {
        // Dedup uses 500ms buckets. Events in different buckets should NOT be deduped.
        let ts1 = Date(timeIntervalSince1970: 200.000)
        let ts2 = Date(timeIntervalSince1970: 200.600)
        let a = TaskActivity(
            type: "agent",
            title: "Planner",
            detail: "step-a",
            payload: ["swarm_id": "planner", "status": "started", "group_id": "swarm-planner"],
            timestamp: ts1,
            phase: .planning,
            isRunning: true,
            groupId: "swarm-planner"
        )
        let b = TaskActivity(
            type: "agent",
            title: "Planner",
            detail: "step-a",
            payload: ["swarm_id": "planner", "status": "started", "group_id": "swarm-planner"],
            timestamp: ts2,
            phase: .planning,
            isRunning: true,
            groupId: "swarm-planner"
        )
        let cards = SwarmLiveReducer.reduce(activities: [a, b], limitRecentEvents: 80)
        XCTAssertEqual(cards["planner"]?.recentEvents.count, 2,
                       "Events 600ms apart should not be deduplicated")
    }

    func testDedupKeyIncludesConversationScope() {
        let timestamp = Date(timeIntervalSince1970: 400.0)
        let conversationA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let conversationB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

        let eventA = TaskActivity(
            type: "agent",
            title: "Planner",
            detail: "started",
            payload: [
                "swarm_id": "planner",
                "group_id": "swarm-planner",
                "status": "started",
                "conversation_id": conversationA.uuidString.lowercased(),
            ],
            timestamp: timestamp,
            phase: .planning,
            isRunning: true,
            groupId: "swarm-planner"
        )

        let eventB = TaskActivity(
            type: "agent",
            title: "Planner",
            detail: "started",
            payload: [
                "swarm_id": "planner",
                "group_id": "swarm-planner",
                "status": "started",
                "conversation_id": conversationB.uuidString.lowercased(),
            ],
            timestamp: timestamp,
            phase: .planning,
            isRunning: true,
            groupId: "swarm-planner"
        )

        let cards = SwarmLiveReducer.reduce(activities: [eventA, eventB], limitRecentEvents: 80)
        XCTAssertEqual(cards["planner"]?.recentEvents.count, 2)
    }

    func testTaskSummaryDoesNotLeakIntoCurrentDetail() {
        let started = TaskActivity(
            type: "agent",
            title: "Explorer-AuthFlow",
            detail: "launching explorer",
            payload: [
                "swarm_id": "Explorer-AuthFlow",
                "group_id": "swarm-Explorer-AuthFlow",
                "agent_name": "Explorer-AuthFlow",
                "task_summary": "Rivedi la pipeline del debug mode lato UI",
                "status": "started",
            ],
            timestamp: Date(timeIntervalSince1970: 500),
            phase: .planning,
            isRunning: true,
            groupId: "swarm-Explorer-AuthFlow"
        )

        let cards = SwarmLiveReducer.reduce(activities: [started], limitRecentEvents: 80)
        XCTAssertEqual(cards["Explorer-AuthFlow"]?.currentDetail, "launching explorer")
    }
}
