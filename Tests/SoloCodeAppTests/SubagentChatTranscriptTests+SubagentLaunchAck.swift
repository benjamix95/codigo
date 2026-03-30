import XCTest
@testable import CoderIDE

final class SubagentChatTranscriptLaunchAckTests: XCTestCase {
    func testLaunchAckCompletedAgentDoesNotProduceTranscriptEntries() {
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
            timestamp: Date(timeIntervalSince1970: 103),
            phase: .executing,
            isRunning: false,
            groupId: "swarm-sa-launch"
        )

        XCTAssertNil(SubagentTranscriptEntry.activity(launchAck))
        XCTAssertNil(SwarmLiveReducer.transcriptEntry(for: launchAck))
    }

    func testRealCompletedAgentStillProducesResultTranscriptEntry() {
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
            timestamp: Date(timeIntervalSince1970: 104),
            phase: .executing,
            isRunning: false,
            groupId: "swarm-sa-real"
        )

        let entry = SwarmLiveReducer.transcriptEntry(for: completed)

        XCTAssertEqual(entry?.kind, .result)
        XCTAssertEqual(entry?.detail, "Review completo: nessuna regressione trovata")
    }
}
