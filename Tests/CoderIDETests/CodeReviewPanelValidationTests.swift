import XCTest
@testable import CoderIDE

final class CodeReviewPanelValidationTests: XCTestCase {

    // MARK: - isValidGitRefFormat

    func testValidRefs() {
        XCTAssertTrue(isValidGitRefFormat("main"))
        XCTAssertTrue(isValidGitRefFormat("HEAD"))
        XCTAssertTrue(isValidGitRefFormat("abc123def"))
        XCTAssertTrue(isValidGitRefFormat("feature/my-branch"))
        XCTAssertTrue(isValidGitRefFormat("v1.0.0"))
        XCTAssertTrue(isValidGitRefFormat("HEAD~3"))
        XCTAssertTrue(isValidGitRefFormat("main..HEAD"))
        XCTAssertTrue(isValidGitRefFormat("feature^"))
    }

    func testEmptyAndWhitespace() {
        XCTAssertFalse(isValidGitRefFormat(""))
        XCTAssertFalse(isValidGitRefFormat("   "))
        XCTAssertFalse(isValidGitRefFormat("\t"))
        XCTAssertFalse(isValidGitRefFormat("\n"))
    }

    func testFlagInjection() {
        XCTAssertFalse(isValidGitRefFormat("-flag"))
        XCTAssertFalse(isValidGitRefFormat("--exec=evil"))
    }

    func testRangeRefsAreAllowed() {
        XCTAssertTrue(isValidGitRefFormat("main..HEAD"))
        XCTAssertTrue(isValidGitRefFormat("a..b"))
    }

    func testForbiddenChars() {
        XCTAssertFalse(isValidGitRefFormat("ref with space"))
        XCTAssertFalse(isValidGitRefFormat("ref:path"))
        XCTAssertFalse(isValidGitRefFormat("ref?"))
        XCTAssertFalse(isValidGitRefFormat("ref*"))
        XCTAssertFalse(isValidGitRefFormat("ref[0]"))
        XCTAssertFalse(isValidGitRefFormat("ref\\path"))
        XCTAssertFalse(isValidGitRefFormat("ref@{0}"))
    }

    func testDotLockSuffix() {
        XCTAssertFalse(isValidGitRefFormat("branch.lock"))
    }

    func testTrailingDot() {
        XCTAssertFalse(isValidGitRefFormat("branch."))
    }

    func testTildeAndCaretAreAllowedForRevisionExpressions() {
        XCTAssertTrue(isValidGitRefFormat("HEAD~3"))
        XCTAssertTrue(isValidGitRefFormat("HEAD^"))
    }

    // MARK: - Review worker activity selection

    func testLatestReviewWorkerPlanBatch_returnsMostRecentContiguousBatch() {
        let base = Date(timeIntervalSinceReferenceDate: 1000)
        let activities: [TaskActivity] = [
            TaskActivity(type: "review-worker-plan", title: "old-1", timestamp: base),
            TaskActivity(type: "review-worker-plan", title: "old-2", timestamp: base.addingTimeInterval(0.5)),
            TaskActivity(type: "analysis-step", title: "separator", timestamp: base.addingTimeInterval(1.0)),
            TaskActivity(type: "review-worker-plan", title: "new-1", timestamp: base.addingTimeInterval(5.0)),
            TaskActivity(type: "review-worker-plan", title: "new-2", timestamp: base.addingTimeInterval(5.4)),
        ]

        let batch = latestReviewWorkerPlanBatch(in: activities)
        XCTAssertEqual(batch.count, 2)
        XCTAssertEqual(batch.map(\.title), ["new-1", "new-2"])
    }

    func testSelectReviewWorkerActivities_prefersPlansAfterLastRoundBoundary() {
        let base = Date(timeIntervalSinceReferenceDate: 2000)
        let activities: [TaskActivity] = [
            TaskActivity(type: "review-worker-plan", title: "pre-1", timestamp: base),
            TaskActivity(type: "review-fix-round", title: "round-1", timestamp: base.addingTimeInterval(1.0)),
            TaskActivity(type: "review-worker-plan", title: "post-1", timestamp: base.addingTimeInterval(2.0)),
            TaskActivity(type: "review-worker-plan", title: "post-2", timestamp: base.addingTimeInterval(2.4)),
        ]

        let selected = selectReviewWorkerActivities(from: activities)
        XCTAssertEqual(selected.map(\.title), ["post-1", "post-2"])
    }

    func testSelectReviewWorkerActivities_fallsBackToLatestPreBoundaryBatch() {
        let base = Date(timeIntervalSinceReferenceDate: 3000)
        let activities: [TaskActivity] = [
            TaskActivity(type: "review-worker-plan", title: "very-old-1", timestamp: base),
            TaskActivity(type: "review-worker-plan", title: "very-old-2", timestamp: base.addingTimeInterval(0.4)),
            TaskActivity(type: "analysis-step", title: "separator", timestamp: base.addingTimeInterval(1.0)),
            TaskActivity(type: "review-worker-plan", title: "latest-1", timestamp: base.addingTimeInterval(4.0)),
            TaskActivity(type: "review-worker-plan", title: "latest-2", timestamp: base.addingTimeInterval(4.6)),
            TaskActivity(type: "review-fix-round", title: "round-1", timestamp: base.addingTimeInterval(6.0)),
        ]

        let selected = selectReviewWorkerActivities(from: activities)
        XCTAssertEqual(selected.count, 2)
        XCTAssertEqual(selected.map(\.title), ["latest-1", "latest-2"])
    }
}
