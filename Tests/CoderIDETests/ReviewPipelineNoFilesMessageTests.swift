import XCTest
@testable import CoderEngine

/// Tests for ReviewPipelineCoordinator.noFilesAgainstRefMessage edge cases,
/// including empty gitRoot/headSHA scenarios.
final class ReviewPipelineNoFilesMessageTests: XCTestCase {

    // MARK: - Error propagation

    func testErrorMessageIsReturnedWhenPresent() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "main",
            normalizedInput: "main",
            currentHeadRevision: nil,
            error: "fatal: bad revision 'main'"
        )
        XCTAssertTrue(msg.contains("fatal: bad revision"))
        XCTAssertTrue(msg.contains("main"))
    }

    func testEmptyErrorStringIsIgnored() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "abc123",
            normalizedInput: "abc123^..abc123",
            currentHeadRevision: nil,
            error: ""
        )
        // Empty error should fall through to the non-error path
        XCTAssertFalse(msg.contains("fatal"))
        XCTAssertTrue(msg.contains("single-commit range"))
    }

    // MARK: - Nil headSHA

    func testNilHeadRevisionDoesNotCrash() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "abc1234",
            normalizedInput: "abc1234^..abc1234",
            currentHeadRevision: nil,
            error: nil
        )
        XCTAssertTrue(msg.contains("single-commit range"))
        XCTAssertFalse(msg.contains("HEAD"))
    }

    // MARK: - Empty headSHA

    /// BUG: Empty headSHA ("") causes `trimmedRef.hasPrefix("")` to be true,
    /// which incorrectly triggers the HEAD-match branch. This test documents
    /// the current (buggy) behavior where empty headSHA is treated as matching.
    func testEmptyHeadRevisionFalselyMatchesRef() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "abc1234",
            normalizedInput: "abc1234^..abc1234",
            currentHeadRevision: "",
            error: nil
        )
        XCTAssertTrue(msg.contains("single-commit range"))
        // BUG: trimmedRef.hasPrefix("") == true, so empty headSHA falsely
        // triggers the HEAD-match branch. This documents the known issue.
        XCTAssertTrue(msg.contains("current `HEAD` commit"),
            "Known bug: empty headSHA causes false HEAD match via hasPrefix(\"\")")
    }

    // MARK: - Single commit range reinterpretation

    func testSingleCommitWithMatchingHead() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "1e72c30",
            normalizedInput: "1e72c30^..1e72c30",
            currentHeadRevision: "1e72c3016738d6e34ad2b79e0c4a1676ded3e234",
            error: nil
        )
        XCTAssertTrue(msg.contains("current `HEAD` commit"))
        XCTAssertTrue(msg.contains("single-commit range"))
    }

    func testSingleCommitWithoutMatchingHead() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "1e72c30",
            normalizedInput: "1e72c30^..1e72c30",
            currentHeadRevision: "aaaaaaa0000000000000000000000000ffffffff",
            error: nil
        )
        XCTAssertFalse(msg.contains("current `HEAD` commit"))
        XCTAssertTrue(msg.contains("single-commit range"))
    }

    // MARK: - Non-single-commit (range input)

    func testRangeRefDoesNotMentionSingleCommit() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "main..feature",
            normalizedInput: "main..feature",
            currentHeadRevision: "abc123",
            error: nil
        )
        XCTAssertFalse(msg.contains("single-commit range"))
        XCTAssertTrue(msg.contains("No changed source files against"))
    }

    // MARK: - Whitespace in ref

    func testWhitespaceInRefIsTrimmed() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "  abc1234  ",
            normalizedInput: "abc1234^..abc1234",
            currentHeadRevision: nil,
            error: nil
        )
        // normalizedInput differs from trimmed ref => single commit branch
        XCTAssertTrue(msg.contains("single-commit range"))
    }
}
