import XCTest
@testable import CoderEngine

final class ReviewSessionRegistryTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        ReviewCoreBridge.resetForTests()
    }

    override func tearDownWithError() throws {
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        ReviewCoreBridge.resetForTests()
        try super.tearDownWithError()
    }

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

    func testDismissFindingUsesRustMutationForLiveSession() async throws {
        try requireReviewCore()
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

    func testAddCommentUsesRustMutationForLiveSession() async throws {
        try requireReviewCore()
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

    func testApplyFixUsesRustMutationForLiveSession() async throws {
        try requireReviewCore()
        let registry = ReviewSessionRegistry()
        let state = CodeReviewSessionState(sessionId: "session-live-apply-fix")
        await state.start(scope: ReviewSessionScope(type: .uncommitted, files: ["File.swift"]))
        await state.addFinding(
            CodeReviewFinding(
                id: "finding-1",
                severity: .warning,
                category: .correctness,
                filePath: "File.swift",
                message: "Apply fix"
            )
        )
        await registry.register(state)

        let didApplyFix = await registry.applyFix(
            sessionId: "session-live-apply-fix",
            findingId: "finding-1"
        )

        XCTAssertTrue(didApplyFix)
        let snapshot = await registry.snapshot(sessionId: "session-live-apply-fix")
        XCTAssertEqual(snapshot?.findings.first?.status, .fixApplied)
        XCTAssertEqual(snapshot?.events.last?.type, .findingFixApplied)
    }

    func testDismissFindingFailsWhenRustMutationRuntimeIsDisabled() async {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()

        let registry = ReviewSessionRegistry()
        let state = CodeReviewSessionState(sessionId: "session-live-dismiss-disabled")
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
        let baseline = await registry.snapshot(sessionId: "session-live-dismiss-disabled")

        let didDismiss = await registry.dismissFinding(
            sessionId: "session-live-dismiss-disabled",
            findingId: "finding-1",
            reason: "wont_fix"
        )

        XCTAssertFalse(didDismiss)
        let snapshot = await registry.snapshot(sessionId: "session-live-dismiss-disabled")
        XCTAssertTrue(snapshot?.findings.isEmpty ?? true)
        XCTAssertEqual(snapshot?.events.count, baseline?.events.count)
        XCTAssertEqual(snapshot?.events.last?.type, baseline?.events.last?.type)
    }

    func testAddCommentFailsWhenRustMutationRuntimeIsDisabled() async {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()

        let registry = ReviewSessionRegistry()
        let state = CodeReviewSessionState(sessionId: "session-live-comment-disabled")
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
        let baseline = await registry.snapshot(sessionId: "session-live-comment-disabled")

        let didComment = await registry.addComment(
            sessionId: "session-live-comment-disabled",
            findingId: "finding-1",
            comment: FindingComment(author: "agent", content: "note from registry")
        )

        XCTAssertFalse(didComment)
        let snapshot = await registry.snapshot(sessionId: "session-live-comment-disabled")
        XCTAssertTrue(snapshot?.findings.isEmpty ?? true)
        XCTAssertEqual(snapshot?.events.count, baseline?.events.count)
        XCTAssertEqual(snapshot?.events.last?.type, baseline?.events.last?.type)
    }

    func testApplyFixFailsWhenRustMutationRuntimeIsDisabled() async {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()

        let registry = ReviewSessionRegistry()
        let state = CodeReviewSessionState(sessionId: "session-live-apply-fix-disabled")
        await state.start(scope: ReviewSessionScope(type: .uncommitted, files: ["File.swift"]))
        await state.addFinding(
            CodeReviewFinding(
                id: "finding-1",
                severity: .warning,
                category: .correctness,
                filePath: "File.swift",
                message: "Apply fix"
            )
        )
        await registry.register(state)
        let baseline = await registry.snapshot(sessionId: "session-live-apply-fix-disabled")

        let didApplyFix = await registry.applyFix(
            sessionId: "session-live-apply-fix-disabled",
            findingId: "finding-1"
        )

        XCTAssertFalse(didApplyFix)
        let snapshot = await registry.snapshot(sessionId: "session-live-apply-fix-disabled")
        XCTAssertTrue(snapshot?.findings.isEmpty ?? true)
        XCTAssertEqual(snapshot?.events.count, baseline?.events.count)
        XCTAssertEqual(snapshot?.events.last?.type, baseline?.events.last?.type)
    }

    func testUpdateConfigUsesRustMutationForLiveSession() async throws {
        try requireReviewCore()
        let registry = ReviewSessionRegistry()
        let state = CodeReviewSessionState(sessionId: "session-live-config")
        await state.start(scope: ReviewSessionScope(type: .uncommitted, files: ["File.swift"]))
        await registry.register(state)

        let didUpdate = await registry.updateConfig(
            sessionId: "session-live-config",
            config: SessionConfig(
                maxWorkers: 4,
                maxRounds: 5,
                analysisBackend: "codex",
                executionBackend: "codex",
                analysisOnly: true
            )
        )

        XCTAssertTrue(didUpdate)
        let snapshot = await registry.snapshot(sessionId: "session-live-config")
        XCTAssertEqual(snapshot?.config.maxWorkers, 4)
        XCTAssertEqual(snapshot?.config.maxRounds, 5)
        XCTAssertTrue(snapshot?.config.analysisOnly == true)
        XCTAssertEqual(snapshot?.events.last?.type, .configUpdated)
    }

    func testBuildOutcomeSummaryCountsPatchStatesAndManualActions() {
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "summary-session",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-1",
                    severity: .warning,
                    category: .correctness,
                    filePath: "File.swift",
                    message: "Issue"
                ),
            ],
            candidates: [
                ReviewCandidate(
                    id: "candidate-1",
                    severity: .warning,
                    category: .correctness,
                    origin: .reviewer,
                    filePath: "File.swift",
                    message: "Candidate",
                    verificationStatus: .inconclusive
                ),
            ],
            patches: [
                ReviewPatchArtifact(
                    id: "patch-1",
                    findingId: "finding-1",
                    patchText: "diff",
                    diffPreview: "@@",
                    touchedFiles: ["File.swift"],
                    status: .verified,
                    prStatus: .opened,
                    mergeStatus: .blocked,
                    conflicts: ["File.swift"]
                ),
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: nil,
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .failed,
            lastUpdatedAt: Date()
        )

        let outcome = snapshot.buildOutcomeSummary()

        XCTAssertEqual(outcome.verifiedFindings, 1)
        XCTAssertEqual(outcome.falsePositives, 0)
        XCTAssertEqual(outcome.patchesReady, 1)
        XCTAssertEqual(outcome.prsOpened, 1)
        XCTAssertEqual(outcome.conflictsDetected, 1)
        XCTAssertTrue(outcome.manualActionRequired)
        XCTAssertEqual(outcome.testsStatus, .failed)
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

    private func requireReviewCore() throws {
        let path = reviewCoreLibraryPathForCodeReviewTests(from: #filePath)
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", path, 1)
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        ReviewCoreBridge.resetForTests()
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Rust review core non disponibile in ambiente.")
        }
    }
}
