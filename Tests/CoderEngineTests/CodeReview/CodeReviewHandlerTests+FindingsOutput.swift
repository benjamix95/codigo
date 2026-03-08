import XCTest
import CoderEngine
@testable import CoderIDEMCPServer

extension CodeReviewHandlerTests {
    func testReviewFindingsOmitsSensitiveDetailsFromOutput() {
        let snapshot = seedSnapshot()

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_findings",
            args: reviewSessionArgs(snapshot)
        )

        XCTAssertNil(result?.isError)
        let text = textContent(result)
        XCTAssertTrue(text.contains("Findings"))
        XCTAssertTrue(text.contains("Redacted"))
        XCTAssertTrue(text.contains("redacted-swift-file-"))
        XCTAssertTrue(text.contains("origin: bugHunter"))
        XCTAssertTrue(text.contains("category: correctness"))
        XCTAssertFalse(text.contains("Package.swift"))
        XCTAssertFalse(text.contains("Test finding"))
        XCTAssertFalse(text.contains("? —"))
    }

    func testReviewFindingsDoesNotFallBackToCompletedSessionWhenNoActiveSessionExists() {
        let conversationId = UUID()
        _ = seedSnapshot(
            sessionId: "completed-findings",
            conversationId: conversationId,
            phase: .completed
        )

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_findings",
            args: ["conversation_id": conversationId.uuidString.lowercased()]
        )

        XCTAssertNil(result?.isError)
        let text = textContent(result)
        XCTAssertTrue(text.contains("No review session found.") || text.contains("No active review session."))
    }
}
