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

    func testReplaceOpenFindingsOnlyTouchesReviewedFiles() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift", "b.swift"])
        await state.start(scope: scope)
        await state.addFindings([
            CodeReviewFinding(id: "open-a", severity: .warning, category: .correctness, filePath: "a.swift", message: "a"),
            CodeReviewFinding(id: "open-b", severity: .warning, category: .correctness, filePath: "b.swift", message: "b"),
        ])

        await state.replaceOpenFindings(
            in: ["a.swift"],
            with: [
                CodeReviewFinding(
                    id: "replacement-a",
                    severity: .critical,
                    category: .security,
                    filePath: "a.swift",
                    message: "new a"
                )
            ]
        )

        let snap = await state.snapshot()
        XCTAssertEqual(
            snap.openFindings.map(\.id).sorted(),
            ["open-b", "replacement-a"]
        )
    }

    func testMarkOpenFindingsAsFixAppliedOnlyTouchesRequestedFiles() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift", "b.swift"])
        await state.start(scope: scope)
        await state.addFindings([
            CodeReviewFinding(id: "open-a", severity: .warning, category: .correctness, filePath: "a.swift", message: "a"),
            CodeReviewFinding(id: "open-b", severity: .warning, category: .correctness, filePath: "b.swift", message: "b"),
        ])

        await state.markOpenFindingsAsFixApplied(in: ["a.swift"])

        let snap = await state.snapshot()
        XCTAssertEqual(
            snap.findings.first(where: { $0.id == "open-a" })?.status,
            .patchApplied
        )
        XCTAssertEqual(
            snap.findings.first(where: { $0.id == "open-b" })?.status,
            .open
        )
    }

    func testMutationSequenceIncreasesAcrossStateChanges() async {
        let state = CodeReviewSessionState()
        let initial = await state.snapshot()
        await state.start(scope: ReviewSessionScope(type: .uncommitted, files: ["a.swift"]))
        let started = await state.snapshot()
        await state.addFinding(CodeReviewFinding(
            severity: .warning,
            category: .correctness,
            filePath: "a.swift",
            message: "test"
        ))
        let updated = await state.snapshot()

        XCTAssertLessThan(initial.mutationSequence, started.mutationSequence)
        XCTAssertLessThan(started.mutationSequence, updated.mutationSequence)
    }
}

final class MCPSharedCodeReviewCommandsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        super.tearDown()
    }

    func testEnqueueCommandDropsInvalidSessionId() {
        let command = MCPSharedState.enqueueCodeReviewCommand(
            action: "start",
            sessionId: "../escape",
            conversationId: nil,
            payload: ["scope": "uncommitted"]
        )
        XCTAssertNil(command.sessionId)
    }

    func testEnqueueCommandDropsSessionIdStartingWithPunctuation() {
        let command = MCPSharedState.enqueueCodeReviewCommand(
            action: "start",
            sessionId: "_session",
            conversationId: nil,
            payload: ["scope": "uncommitted"]
        )
        XCTAssertNil(command.sessionId)
    }

    func testClaimPendingCommandsPromotesThemToProcessing() throws {
        _ = MCPSharedState.enqueueCodeReviewCommand(action: "start", sessionId: "session-1", conversationId: nil, payload: ["scope": "uncommitted"])
        _ = MCPSharedState.enqueueCodeReviewCommand(action: "configure", sessionId: "session-1", conversationId: nil, payload: ["max_workers": "4"])
        let claimed = MCPSharedState.claimPendingCodeReviewCommands()
        XCTAssertEqual(claimed.count, 2)
        XCTAssertTrue(claimed.allSatisfy { $0.status == .processing })
        XCTAssertTrue(MCPSharedState.readPendingCodeReviewCommands().isEmpty)
    }

    func testEnqueueUniqueStartRejectsDuplicatePendingSessionId() throws {
        _ = try MCPSharedState.enqueueUniqueCodeReviewStartCommand(
            sessionId: "session-1",
            conversationId: nil,
            payload: ["scope": "uncommitted"]
        )
        XCTAssertThrowsError(
            try MCPSharedState.enqueueUniqueCodeReviewStartCommand(
                sessionId: "session-1",
                conversationId: nil,
                payload: ["scope": "staged"]
            )
        ) { error in
            XCTAssertEqual(error as? MCPSharedState.CodeReviewStartEnqueueError, .sessionAlreadyQueued)
        }
    }

    func testClaimPendingCommandsReclaimsStaleProcessingCommands() throws {
        try FileManager.default.createDirectory(at: MCPSharedState.codeReviewDirectoryPath, withIntermediateDirectories: true)
        let stale = MCPSharedCodeReviewCommand(
            id: "cmd-1",
            action: "comment",
            sessionId: "session-1",
            conversationId: nil,
            payload: ["finding_id": "f1"],
            createdAt: Date(timeIntervalSinceNow: -600),
            updatedAt: Date(timeIntervalSinceNow: -600),
            status: .processing,
            resultMessage: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([stale]).write(to: MCPSharedState.codeReviewCommandsFilePath, options: .atomic)

        let claimed = MCPSharedState.claimPendingCodeReviewCommands()
        XCTAssertEqual(claimed.map(\.id), ["cmd-1"])
        XCTAssertEqual(claimed.first?.status, .processing)
    }

    func testHeartbeatRefreshPreventsStaleProcessingCommandFromBeingReclaimed() throws {
        try FileManager.default.createDirectory(at: MCPSharedState.codeReviewDirectoryPath, withIntermediateDirectories: true)
        let stale = MCPSharedCodeReviewCommand(
            id: "cmd-heartbeat",
            action: "start",
            sessionId: "session-1",
            conversationId: nil,
            payload: ["scope": "uncommitted"],
            createdAt: Date(timeIntervalSinceNow: -600),
            updatedAt: Date(timeIntervalSinceNow: -600),
            status: .processing,
            resultMessage: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([stale]).write(to: MCPSharedState.codeReviewCommandsFilePath, options: .atomic)

        MCPSharedState.refreshCodeReviewCommandHeartbeat(id: "cmd-heartbeat")
        XCTAssertTrue(MCPSharedState.claimPendingCodeReviewCommands().isEmpty)
    }
}
