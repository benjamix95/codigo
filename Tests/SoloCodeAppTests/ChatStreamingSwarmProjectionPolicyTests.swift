import XCTest
@testable import CoderIDE

final class ChatStreamingSwarmProjectionPolicyTests: XCTestCase {
    func testGenericAgentEventWithoutSwarmMetadataDoesNotProjectIntoSwarmUI() {
        XCTAssertFalse(
            shouldProjectAgentEventIntoSwarmUI([
                "title": "Agent",
                "detail": "started",
                "status": "started",
            ])
        )
    }

    func testAgentEventWithSwarmMetadataProjectsIntoSwarmUI() {
        XCTAssertTrue(
            shouldProjectAgentEventIntoSwarmUI([
                "title": "Explorer-AuthFlow",
                "detail": "started",
                "status": "started",
                "swarm_id": "Explorer-AuthFlow",
                "group_id": "swarm-Explorer-AuthFlow",
            ])
        )
    }
}
