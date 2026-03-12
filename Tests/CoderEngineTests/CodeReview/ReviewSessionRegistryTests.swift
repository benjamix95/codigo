import XCTest
@testable import CoderEngine

final class ReviewSessionRegistryTests: XCTestCase {
    func testLatestSnapshotPrefersNewestTimestampAcrossSessions() async {
        let registry = ReviewSessionRegistry()
        let conversationId = UUID()
        let olderButHigherMutation = makeSnapshot(
            sessionId: "older",
            conversationId: conversationId,
            mutationSequence: 99,
            lastUpdatedAt: Date(timeIntervalSinceNow: -60)
        )
        let newer = makeSnapshot(
            sessionId: "newer",
            conversationId: conversationId,
            mutationSequence: 1,
            lastUpdatedAt: Date()
        )

        await registry.recordSnapshot(olderButHigherMutation)
        await registry.recordSnapshot(newer)

        let latest = await registry.latestSnapshot(conversationId: conversationId)
        XCTAssertEqual(latest?.sessionId, "newer")
    }

    func testUnregisterRemovesSnapshotAndConversationIndex() async {
        let registry = ReviewSessionRegistry()
        let conversationId = UUID()
        let sessionId = "session-to-remove"

        await registry.recordSnapshot(
            makeSnapshot(
                sessionId: sessionId,
                conversationId: conversationId,
                mutationSequence: 1,
                lastUpdatedAt: Date()
            )
        )

        await registry.unregister(sessionId: sessionId)

        let snapshot = await registry.snapshot(sessionId: sessionId)
        let snapshots = await registry.snapshots(conversationId: conversationId)
        XCTAssertNil(snapshot)
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testDismissFindingUsesRustMutationForLiveSession() async {
        let registry = ReviewSessionRegistry()
        let state = CodeReviewSessionState(sessionId: "session-live-dismiss")
        await state.start(scope: ReviewSessionScope(type: .uncommitted, files: ["File.swift"]))
        await state.addFinding(
            CodeReviewFinding(
                id: "finding-1",
                severity: .warning,
                category: .correctness,
                filePath: "File.swift",
                message: "Dismiss me"
            )
        )
        await registry.register(state)

        let didDismiss = await registry.dismissFinding(
            sessionId: "session-live-dismiss",
            findingId: "finding-1",
            reason: "wont_fix"
        )

        XCTAssertTrue(didDismiss)
        let snapshot = await registry.snapshot(sessionId: "session-live-dismiss")
        XCTAssertEqual(snapshot?.findings.first?.status, .wontFix)
        XCTAssertEqual(snapshot?.events.last?.type, .findingDismissed)
    }

    func testAddCommentUsesRustMutationForLiveSession() async {
        let registry = ReviewSessionRegistry()
        let state = CodeReviewSessionState(sessionId: "session-live-comment")
        await state.start(scope: ReviewSessionScope(type: .uncommitted, files: ["File.swift"]))
        await state.addFinding(
            CodeReviewFinding(
                id: "finding-1",
                severity: .warning,
                category: .correctness,
                filePath: "File.swift",
                message: "Comment me"
            )
        )
        await registry.register(state)

        let didComment = await registry.addComment(
            sessionId: "session-live-comment",
            findingId: "finding-1",
            comment: FindingComment(author: "agent", content: "note from registry")
        )

        XCTAssertTrue(didComment)
        let snapshot = await registry.snapshot(sessionId: "session-live-comment")
        XCTAssertEqual(snapshot?.findings.first?.comments.last?.content, "note from registry")
        XCTAssertEqual(snapshot?.events.last?.type, .findingCommented)
    }

    private func makeSnapshot(
        sessionId: String,
        conversationId: UUID,
        mutationSequence: UInt64,
        lastUpdatedAt: Date
    ) -> CodeReviewSessionSnapshot {
        CodeReviewSessionSnapshot(
            sessionId: sessionId,
            conversationId: conversationId,
            mutationSequence: mutationSequence,
            phase: .fixing,
            stage: .fixing,
            findings: [],
            events: [],
            config: .default,
            scope: ReviewSessionScope(type: .uncommitted, files: ["File.swift"]),
            workspacePath: FileManager.default.currentDirectoryPath,
            currentRound: 1,
            activeWorkerCount: 1,
            startedAt: Date(),
            completedAt: nil,
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: "job-1",
            lastTestStatus: nil,
            lastUpdatedAt: lastUpdatedAt
        )
    }
}
