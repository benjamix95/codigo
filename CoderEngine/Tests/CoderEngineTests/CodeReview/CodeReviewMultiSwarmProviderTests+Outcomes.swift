import XCTest
@testable import CoderEngine

extension CodeReviewMultiSwarmProviderTests {
    // MARK: - gitDiffFiles argument order

    func testGitDiffFiles_invalidRef_returnsError() {
        // Use a non-existent directory to trigger a git error, confirming the
        // function surfaces errors correctly rather than silently returning empty.
        let bogusPath = URL(fileURLWithPath: "/tmp/nonexistent-repo-\(UUID().uuidString)")
        let (files, error) = CodeReviewMultiSwarmProvider.gitDiffFiles(ref: "HEAD~1", workspacePath: bogusPath)
        XCTAssertTrue(files.isEmpty)
        XCTAssertNotNil(error)
    }

    // MARK: - findingsContainIssues

    func testFindingsContainIssues_cleanPhraseOnly_returnsClean() {
        let state = CodeReviewMultiSwarmProvider.findingsStateDebugLabel(
            for: "No issues found. Everything looks good."
        )
        XCTAssertEqual(state, "clean")
    }

    func testFindingsContainIssues_noCriticalIssuesPhrase_doesNotFalsePositive() {
        let state = CodeReviewMultiSwarmProvider.findingsStateDebugLabel(
            for:
            "No critical issues found in the reviewed files."
        )
        XCTAssertEqual(state, "clean")
    }

    func testFindingsContainIssues_mixedCleanAndIssueText_returnsIssues() {
        let text = "No critical issues in module A, but a security vulnerability remains in auth flow."
        let state = CodeReviewMultiSwarmProvider.findingsStateDebugLabel(for: text)
        XCTAssertEqual(state, "issues")
    }

    func testFindingsContainIssues_previousFixPhrase_doesNotFalsePositive() {
        let text = "The previous fix was applied correctly and no remaining issues were found."
        let state = CodeReviewMultiSwarmProvider.findingsStateDebugLabel(for: text)
        XCTAssertEqual(state, "clean")
    }

    // MARK: - worker ordering

    func testSortedWorkerTaskIDsForDisplay_usesNaturalOrdering() {
        let ids = ["review-10", "review-2", "review-1"]
        let sorted = CodeReviewMultiSwarmProvider.sortedWorkerTaskIDsForDisplay(ids)
        XCTAssertEqual(sorted, ["review-1", "review-2", "review-10"])
    }

    // MARK: - test failure output detection

    func testOutputSignalsTestFailure_ignoresGenericErrorToken() {
        let output = "Build completed. Notes: error: keyword appears in docs only."
        XCTAssertFalse(CodeReviewMultiSwarmProvider.outputSignalsTestFailure(output))
    }

    func testOutputSignalsTestFailure_detectsJestFailLine() {
        let output = """
        FAIL src/review/provider.test.ts
        Test Suites: 1 failed, 3 passed, 4 total
        """
        XCTAssertTrue(CodeReviewMultiSwarmProvider.outputSignalsTestFailure(output))
    }
}
