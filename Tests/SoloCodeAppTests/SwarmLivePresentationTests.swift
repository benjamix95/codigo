import XCTest
@testable import CoderIDE

final class SwarmLivePresentationTests: XCTestCase {
    func testNormalizedSubtitleRejectsRawSubagentMCPLabel() {
        let text = SwarmLivePresentation.normalizedSubtitleText(
            "MCP call • coderide/coderide_subagent_explorer"
        )

        XCTAssertNil(text)
    }

    func testNormalizedSubtitleRejectsTaskPayloadJSON() {
        let text = SwarmLivePresentation.normalizedSubtitleText(
            #"{"task":"Rivedi la pipeline del debug mode"}"#
        )

        XCTAssertNil(text)
    }

    func testLatestMeaningfulLiveLineUsesOperationalOutput() {
        let line = SwarmLivePresentation.latestMeaningfulLiveLine(
            from: """
            started
            read App/SoloCodeApp/Sources/Swarm/SwarmLiveReducer.swift
            """
        )

        XCTAssertEqual(line, "read App/SoloCodeApp/Sources/Swarm/SwarmLiveReducer.swift")
    }

    func testWorkerPresentationRoleDisplaysPlannerAsSubagentWorker() {
        XCTAssertEqual(
            SubagentChatCardHelpers.roleDisplayName(from: "planner"),
            "Planner"
        )
    }
}
