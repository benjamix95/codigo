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
