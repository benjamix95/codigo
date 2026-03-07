import XCTest
@testable import CoderEngine

final class MCPSharedCodeReviewSnapshotStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        super.tearDown()
    }

    func testReadSnapshotsRebuildsFromSessionFilesWhenIndexIsCorrupted() throws {
        let snapshot = makeSnapshot(sessionId: "session-1", lastUpdatedAt: Date())
        MCPSharedState.writeCodeReviewSnapshot(snapshot)
        try Data("not-json".utf8).write(to: MCPSharedState.codeReviewIndexFilePath, options: .atomic)

        let snapshots = MCPSharedState.readCodeReviewSnapshots(
            conversationId: snapshot.conversationId
        )

        XCTAssertEqual(snapshots.map(\.sessionId), ["session-1"])
    }

    func testLatestSessionIdUsesSnapshotTimestamps() {
        let conversationId = UUID()
        let older = makeSnapshot(
            sessionId: "session-old",
            conversationId: conversationId,
            lastUpdatedAt: Date(timeIntervalSinceNow: -60)
        )
        let newer = makeSnapshot(
            sessionId: "session-new",
            conversationId: conversationId,
            lastUpdatedAt: Date()
        )
        MCPSharedState.writeCodeReviewSnapshot(older)
        MCPSharedState.writeCodeReviewSnapshot(newer)

        let latest = MCPSharedState.latestCodeReviewSessionId(
            conversationId: newer.conversationId
        )

        XCTAssertEqual(latest, "session-new")
    }


    func testWriteSnapshotIgnoresInvalidSessionId() {
        let snapshot = makeSnapshot(sessionId: "../escape", lastUpdatedAt: Date())

        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: MCPSharedState.codeReviewSessionFilePath(sessionId: "../escape").path)
        )
        XCTAssertTrue(MCPSharedState.readCodeReviewSnapshots().isEmpty)
    }

    func testWriteSnapshotIgnoresOlderMutationSequence() {
        let conversationId = UUID()
        let newer = makeSnapshot(
            sessionId: "session-ordered",
            conversationId: conversationId,
            lastUpdatedAt: Date()
        )
        let older = CodeReviewSessionSnapshot(
            sessionId: newer.sessionId,
            conversationId: newer.conversationId,
            mutationSequence: newer.mutationSequence - 1,
            phase: .failed,
            stage: .failed,
            findings: [],
            events: [],
            config: .default,
            scope: newer.scope,
            workspacePath: newer.workspacePath,
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: newer.startedAt,
            completedAt: Date(),
            analysisCompletedAt: newer.analysisCompletedAt,
            lastError: "stale",
            currentJobId: nil,
            lastTestStatus: nil,
            lastUpdatedAt: Date(timeIntervalSinceNow: 60)
        )

        MCPSharedState.writeCodeReviewSnapshot(newer)
        MCPSharedState.writeCodeReviewSnapshot(older)

        let loaded = MCPSharedState.readCodeReviewSnapshot(sessionId: newer.sessionId)
        XCTAssertEqual(loaded?.phase, .fixing)
        XCTAssertEqual(loaded?.mutationSequence, newer.mutationSequence)
    }

    private func makeSnapshot(
        sessionId: String,
        conversationId: UUID = UUID(),
        lastUpdatedAt: Date
    ) -> CodeReviewSessionSnapshot {
        return CodeReviewSessionSnapshot(
            sessionId: sessionId,
            conversationId: conversationId,
            mutationSequence: 3,
            phase: .fixing,
            stage: .fixing,
            findings: [
                CodeReviewFinding(
                    id: "f123",
                    severity: .warning,
                    category: .bug,
                    filePath: "Package.swift",
                    message: "Test finding"
                )
            ],
            events: [.sessionStarted(scope: "uncommitted changes", fileCount: 1)],
            config: .default,
            scope: ReviewSessionScope(type: .uncommitted, files: ["Package.swift"]),
            workspacePath: FileManager.default.currentDirectoryPath,
            currentRound: 1,
            activeWorkerCount: 1,
            startedAt: Date(),
            completedAt: nil,
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: "job-1",
            lastTestStatus: .passed,
            lastUpdatedAt: lastUpdatedAt
        )
    }
}
