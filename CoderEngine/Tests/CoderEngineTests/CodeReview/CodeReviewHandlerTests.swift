import XCTest
import MCP
@testable import CoderIDEMCPServer

final class CodeReviewHandlerTests: XCTestCase {

    // MARK: - review_start

    func testReviewStartDefaultScope() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_start",
            args: [:]
        )
        XCTAssertNotNil(result)
        XCTAssertNil(result?.isError)
        XCTAssertTrue(textContent(result).contains("uncommitted"))
    }

    func testReviewStartExplicitScope() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_start",
            args: ["scope": "staged"]
        )
        XCTAssertNil(result?.isError)
        XCTAssertTrue(textContent(result).contains("staged"))
    }

    func testReviewStartAgainstRefRequiresRef() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_start",
            args: ["scope": "against_ref"]
        )
        XCTAssertEqual(result?.isError, true)
        XCTAssertTrue(textContent(result).contains("ref"))
    }

    func testReviewStartAgainstRefWithRef() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_start",
            args: ["scope": "against_ref", "ref": "main"]
        )
        XCTAssertNil(result?.isError)
    }

    func testReviewStartInvalidScope() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_start",
            args: ["scope": "invalid"]
        )
        XCTAssertEqual(result?.isError, true)
    }

    func testReviewStartInvalidMaxWorkers() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_start",
            args: ["max_workers": "99"]
        )
        XCTAssertEqual(result?.isError, true)
    }

    // MARK: - review_status

    func testReviewStatus() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_status",
            args: [:]
        )
        XCTAssertNil(result?.isError)
    }

    // MARK: - review_findings

    func testReviewFindingsNoFilters() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_findings",
            args: [:]
        )
        XCTAssertNil(result?.isError)
    }

    func testReviewFindingsInvalidSeverity() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_findings",
            args: ["severity": "extreme"]
        )
        XCTAssertEqual(result?.isError, true)
    }

    func testReviewFindingsInvalidStatus() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_findings",
            args: ["status": "unknown"]
        )
        XCTAssertEqual(result?.isError, true)
    }

    // MARK: - review_apply_fix

    func testReviewApplyFixRequiresFindingId() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_apply_fix",
            args: [:]
        )
        XCTAssertEqual(result?.isError, true)
    }

    func testReviewApplyFixWithId() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_apply_fix",
            args: ["finding_id": "f123"]
        )
        XCTAssertNil(result?.isError)
        XCTAssertTrue(textContent(result).contains("f123"))
    }

    // MARK: - review_dismiss

    func testReviewDismissRequiresFindingId() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_dismiss",
            args: [:]
        )
        XCTAssertEqual(result?.isError, true)
    }

    func testReviewDismissWithValidReason() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_dismiss",
            args: ["finding_id": "f1", "reason": "false_positive"]
        )
        XCTAssertNil(result?.isError)
    }

    func testReviewDismissInvalidReason() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_dismiss",
            args: ["finding_id": "f1", "reason": "invalid_reason"]
        )
        XCTAssertEqual(result?.isError, true)
    }

    // MARK: - review_configure

    func testReviewConfigureNoParams() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_configure",
            args: [:]
        )
        XCTAssertEqual(result?.isError, true)
    }

    func testReviewConfigureValidParams() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_configure",
            args: ["max_workers": "8", "max_rounds": "5"]
        )
        XCTAssertNil(result?.isError)
        XCTAssertTrue(textContent(result).contains("max_workers=8"))
    }

    // MARK: - review_diff_summary

    func testReviewDiffSummary() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_diff_summary",
            args: [:]
        )
        XCTAssertNil(result?.isError)
    }

    // MARK: - review_comment

    func testReviewCommentRequiresBothParams() {
        let result1 = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_comment",
            args: ["finding_id": "f1"]
        )
        XCTAssertEqual(result1?.isError, true)

        let result2 = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_comment",
            args: ["content": "comment"]
        )
        XCTAssertEqual(result2?.isError, true)
    }

    func testReviewCommentSuccess() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_comment",
            args: ["finding_id": "f1", "content": "Looks good"]
        )
        XCTAssertNil(result?.isError)
    }

    // MARK: - Unknown tool

    func testUnknownToolReturnsNil() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "nonexistent_tool",
            args: [:]
        )
        XCTAssertNil(result)
    }

    // MARK: - Helpers

    private func textContent(_ result: MCP.CallTool.Result?) -> String {
        guard let content = result?.content.first else { return "" }
        if case .text(let text) = content {
            return text
        }
        return ""
    }
}
