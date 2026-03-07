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

    func testBranchScopeTagProducesValidRefExpression() {
        if case .branch(let ref) = ReviewScopeTarget.branch("feature/refactor") {
            XCTAssertEqual(ref, "feature/refactor")
            XCTAssertTrue(isValidGitRefFormat(ReviewScopeTarget.branch("feature/refactor").scopeTag.replacingOccurrences(of: "[AGAINST:", with: "").replacingOccurrences(of: "]", with: "")))
        } else {
            XCTFail("Expected branch scope")
        }
    }

    func testCommitRangeScopeTagProducesValidRangeExpression() {
        let target = ReviewScopeTarget.commits(["def456", "abc123"])
        let rawRef = target.scopeTag
            .replacingOccurrences(of: "[AGAINST:", with: "")
            .replacingOccurrences(of: "]", with: "")
        XCTAssertEqual(rawRef, "abc123^..def456")
        XCTAssertTrue(isValidGitRefFormat(rawRef))
    }

    func testCustomCommandNormalizesLeadingSlashAway() {
        let command = ReviewPanelCustomCommand(
            name: "Deep Review",
            slash: "/deep-review",
            prompt: "Review everything"
        )

        XCTAssertEqual(command.slash, "deep-review")
        XCTAssertEqual(command.displayCommand, "deep-review")
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

    func testSortedReviewWorkerPlanActivitiesForDisplay_usesNaturalWorkerOrdering() {
        let base = Date(timeIntervalSinceReferenceDate: 4000)
        let activities: [TaskActivity] = [
            TaskActivity(type: "review-worker-plan", title: "w10", payload: ["worker_id": "review-10"], timestamp: base.addingTimeInterval(0.2)),
            TaskActivity(type: "review-worker-plan", title: "w2", payload: ["worker_id": "review-2"], timestamp: base.addingTimeInterval(0.1)),
            TaskActivity(type: "review-worker-plan", title: "w1", payload: ["worker_id": "review-1"], timestamp: base),
        ]

        let sorted = sortedReviewWorkerPlanActivitiesForDisplay(activities)
        XCTAssertEqual(sorted.map(\.title), ["w1", "w2", "w10"])
    }

    func testScopedTaskActivitiesForConversation_filtersMismatchedConversation() {
        let convA = UUID()
        let convB = UUID()
        let activities: [TaskActivity] = [
            TaskActivity(type: "review-worker-plan", title: "a", payload: ["conversation_id": convA.uuidString.lowercased()]),
            TaskActivity(type: "review-worker-plan", title: "b", payload: ["conversation_id": convB.uuidString.lowercased()]),
            TaskActivity(type: "review-worker-plan", title: "untagged"),
        ]

        let scoped = scopedTaskActivitiesForConversation(activities, conversationId: convA)
        XCTAssertEqual(scoped.map(\.title), ["a"])
    }

    func testScopedTaskActivitiesForConversation_acceptsCamelCaseConversationId() {
        let convA = UUID()
        let convB = UUID()
        let activities: [TaskActivity] = [
            TaskActivity(type: "review-worker-plan", title: "a", payload: ["conversationId": convA.uuidString.lowercased()]),
            TaskActivity(type: "review-worker-plan", title: "b", payload: ["conversationId": convB.uuidString.lowercased()])
        ]

        let scoped = scopedTaskActivitiesForConversation(activities, conversationId: convA)
        XCTAssertEqual(scoped.map(\.title), ["a"])
    }

    func testReviewCardBelongsToConversation_checksRecentEventConversation() {
        let convA = UUID()
        let convB = UUID()
        let cardForB = SwarmLiveCardState(
            swarmId: "review-2",
            recentEvents: [
                TaskActivity(
                    type: "agent",
                    title: "worker",
                    payload: ["conversation_id": convB.uuidString.lowercased()]
                )
            ]
        )

        XCTAssertFalse(reviewCardBelongsToConversation(cardForB, conversationId: convA))
        XCTAssertTrue(reviewCardBelongsToConversation(cardForB, conversationId: convB))
    }

    func testReviewCardBelongsToConversation_acceptsCamelCaseConversationId() {
        let conversationId = UUID()
        let card = SwarmLiveCardState(
            swarmId: "review-3",
            recentEvents: [
                TaskActivity(
                    type: "agent",
                    title: "worker",
                    payload: ["conversationId": conversationId.uuidString.uppercased()]
                )
            ]
        )

        XCTAssertTrue(reviewCardBelongsToConversation(card, conversationId: conversationId))
    }

    func testScopedReviewActivitiesForSession_filtersMismatchedSession() {
        let activities: [TaskActivity] = [
            TaskActivity(type: "review-worker-plan", title: "a", payload: ["session_id": "s1"]),
            TaskActivity(type: "review-worker-plan", title: "b", payload: ["session_id": "s2"]),
        ]

        let scoped = scopedReviewActivitiesForSession(activities, sessionId: "s1")
        XCTAssertEqual(scoped.map(\.title), ["a"])
    }

    func testReviewCardBelongsToSession_filtersMismatchedSession() {
        let card = SwarmLiveCardState(
            swarmId: "worker",
            recentEvents: [
                TaskActivity(type: "agent", title: "a", payload: ["session_id": "s1"])
            ]
        )

        XCTAssertTrue(reviewCardBelongsToSession(card, sessionId: "s1"))
        XCTAssertFalse(reviewCardBelongsToSession(card, sessionId: "s2"))
    }

    func testShouldDisplayCodeReviewMetricsWhenConversationStillHasReviewArtifacts() {
        XCTAssertTrue(
            shouldDisplayCodeReviewMetrics(
                isRunning: false,
                hasReviewArtifacts: true
            )
        )
    }

    func testShouldDisplayCodeReviewMetricsStaysHiddenWithoutModeOrArtifacts() {
        XCTAssertFalse(
            shouldDisplayCodeReviewMetrics(
                isRunning: false,
                hasReviewArtifacts: false
            )
        )
    }

    func testShouldUseCodeReviewRuntimeProviderHonorsExplicitOverride() {
        XCTAssertTrue(
            shouldUseCodeReviewRuntimeProvider(
                coderMode: .agent,
                preferredOverride: true
            )
        )
        XCTAssertFalse(
            shouldUseCodeReviewRuntimeProvider(
                coderMode: .codeReviewMultiSwarm,
                preferredOverride: false
            )
        )
    }

    func testHasCodeReviewArtifactsAcceptsRoundOnlyHistory() {
        let activities = [
            TaskActivity(
                type: "review-fix-round",
                title: "round-1",
                payload: ["round": "1", "maxRounds": "3"]
            )
        ]

        XCTAssertTrue(
            hasCodeReviewArtifactsCheck(
                cards: [],
                workerActivities: [],
                activities: activities
            )
        )
    }
}
