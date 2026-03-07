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

    func testReviewFindingsFallsBackToConversationScopedSessionWhenConversationIdIsOmitted() {
        let snapshot = seedSnapshot(phase: .analyzing)

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_findings",
            args: [:]
        )

        XCTAssertNil(result?.isError)
        XCTAssertTrue(textContent(result).contains(snapshot.findings[0].message))
    }

    func testReviewDiffSummaryFallsBackToConversationScopedSessionWhenConversationIdIsOmitted() {
        let snapshot = seedSnapshot(phase: .analyzing)

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_diff_summary",
            args: [:]
        )

        XCTAssertNil(result?.isError)
        XCTAssertFalse(textContent(result).contains("conversation_id"))
        XCTAssertFalse(textContent(result).contains("No active review session."))
        XCTAssertTrue(
            textContent(result).contains("No diff data available")
                || textContent(result).contains(snapshot.sessionId)
        )
    }
}
