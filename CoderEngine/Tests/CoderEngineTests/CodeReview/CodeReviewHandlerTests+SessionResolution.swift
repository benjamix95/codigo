import XCTest
import CoderEngine
@testable import CoderIDEMCPServer

extension CodeReviewHandlerTests {
    func testReviewStatusFallsBackToConversationScopedSessionWhenConversationIdIsOmitted() {
        let snapshot = seedSnapshot(phase: .analyzing)

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_status",
            args: [:]
        )

        XCTAssertNil(result?.isError)
        XCTAssertFalse(textContent(result).contains("No active review session."))
        XCTAssertTrue(textContent(result).contains("session_id: \(snapshot.sessionId)"))
    }
}
