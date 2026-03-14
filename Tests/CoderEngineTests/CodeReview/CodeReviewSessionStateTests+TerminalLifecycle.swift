import XCTest
@testable import CoderEngine

extension CodeReviewSessionStateTests {
    func testCompleteClearsCurrentJobId() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])

        await state.start(scope: scope)
        await state.setCurrentJobId("job-123")
        await state.complete()

        let snapshot = await state.snapshot()
        XCTAssertNil(snapshot.currentJobId)
        XCTAssertEqual(snapshot.activeWorkerCount, 0)
    }

    func testFailClearsCurrentJobId() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])

        await state.start(scope: scope)
        await state.setCurrentJobId("job-123")
        await state.fail(error: "boom")

        let snapshot = await state.snapshot()
        XCTAssertNil(snapshot.currentJobId)
        XCTAssertEqual(snapshot.activeWorkerCount, 0)
    }

    func testReplaceCanonicalSnapshotReplacesStateForMatchingSession() async {
        let state = CodeReviewSessionState(sessionId: "session-rust-snapshot")
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-rust-snapshot",
            conversationId: nil,
            mutationSequence: 42,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-1",
                    severity: .warning,
                    category: .correctness,
                    filePath: "File.swift",
                    message: "done"
                )
            ],
            events: [],
            config: SessionConfig(maxWorkers: 4, maxRounds: 2),
            scope: ReviewSessionScope(type: .workspace, files: ["File.swift"]),
            workspacePath: "/tmp/review",
            currentRound: 2,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            lastUpdatedAt: Date()
        )

        await state.replaceCanonicalSnapshot(snapshot)

        let updated = await state.snapshot()
        XCTAssertEqual(updated.mutationSequence, 42)
        XCTAssertEqual(updated.phase, .completed)
        XCTAssertEqual(updated.findings.map(\.id), ["finding-1"])
        XCTAssertEqual(updated.config.maxWorkers, 4)
        XCTAssertEqual(updated.scope?.type, .workspace)
    }
}
