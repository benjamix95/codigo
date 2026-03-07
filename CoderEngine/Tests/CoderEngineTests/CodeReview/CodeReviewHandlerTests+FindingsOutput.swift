import XCTest
import CoderEngine
@testable import CoderIDEMCPServer

extension CodeReviewHandlerTests {
    func testReviewFindingsIncludesSensitiveDetailsAfterAuthorization() {
        let snapshot = seedSnapshot()

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_findings",
            args: reviewSessionArgs(snapshot)
        )

        XCTAssertNil(result?.isError)
        let text = textContent(result)
        XCTAssertTrue(text.contains("Package.swift"))
        XCTAssertTrue(text.contains("Test finding"))
    }

    func testReviewFindingsFallsBackToCompletedSessionWhenUnique() {
        let conversationId = UUID()
        let completed = seedSnapshot(
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
        XCTAssertTrue(text.contains(completed.sessionId) || text.contains("Package.swift"))
    }
}
