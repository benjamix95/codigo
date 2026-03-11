import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class CodigoAppCodeReviewCommandLoopTests: XCTestCase {
    private var workspaceURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        CodeReviewCommandRuntimeHooks.providerFactoryOverride = nil
        CodeReviewCommandRuntimeHooks.workspaceContextOverride = nil
        workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codigo-review-command-loop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        CodeReviewCommandRuntimeHooks.providerFactoryOverride = nil
        CodeReviewCommandRuntimeHooks.workspaceContextOverride = nil
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        if let workspaceURL {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        workspaceURL = nil
        try super.tearDownWithError()
    }

    func testStartCommandRemainsProcessingUntilDeferredReviewCompletes() async throws {
        let app = makeApp()
        let gate = ReviewProviderGate()
        CodeReviewCommandRuntimeHooks.workspaceContextOverride = { [workspaceURL] _ in
            WorkspaceContext(workspacePaths: [workspaceURL].compactMap { $0 })
        }
        CodeReviewCommandRuntimeHooks.providerFactoryOverride = { _, _, _, _, _, sessionState, _ in
            DeferredCodeReviewProvider(
                sessionState: sessionState,
                gate: gate,
                scopeFiles: ["Sources/File.swift"]
            )
        }

        let command = try MCPSharedState.enqueueUniqueCodeReviewStartCommand(
            sessionId: "review-start-deferred",
            conversationId: nil,
            payload: [
                "scope": "uncommitted",
                "session_id": "review-start-deferred",
            ]
        )

        await app.processPendingCodeReviewCommandsOnce()

        let current = try currentCommand(id: command.id)
        XCTAssertEqual(current?.status, .processing, current?.resultMessage ?? "missing result message")
        let inFlightSnapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: "review-start-deferred")
        XCTAssertNotNil(inFlightSnapshot)

        await gate.finishSuccessfully()
        try await waitForCommand(id: command.id, expectedStatus: .completed)

        let completedSnapshot = try XCTUnwrap(
            MCPSharedState.readCodeReviewSnapshot(sessionId: "review-start-deferred")
        )
        XCTAssertEqual(completedSnapshot.phase, .completed)
    }

    func testApplyFixCommandFailsClosedWhenPatchWorkflowCannotRun() async throws {
        let app = makeApp()

        let sourceSnapshot = makeSnapshot(
            sessionId: "source-review",
            findings: [
                CodeReviewFinding(
                    id: "finding-1",
                    severity: .warning,
                    category: .bug,
                    filePath: "Sources/File.swift",
                    message: "Needs a real fix"
                )
            ]
        )
        MCPSharedState.writeCodeReviewSnapshot(sourceSnapshot)

        let command = MCPSharedState.enqueueCodeReviewCommand(
            action: "apply_fix",
            sessionId: sourceSnapshot.sessionId,
            conversationId: nil,
            payload: [
                "finding_id": "finding-1",
                "session_id": sourceSnapshot.sessionId,
            ]
        )

        await app.processPendingCodeReviewCommandsOnce()

        XCTAssertEqual(try currentCommand(id: command.id)?.status, .failed)
        let updatedSnapshot = try XCTUnwrap(
            MCPSharedState.readCodeReviewSnapshot(sessionId: sourceSnapshot.sessionId)
        )
        XCTAssertEqual(updatedSnapshot.findings.first?.status, .open)
    }

    func testConfigureCommandUpdatesLiveSessionThroughCommandLoop() async throws {
        let app = makeApp()
        CodeReviewCommandRuntimeHooks.providerFactoryOverride = { _, _, _, _, _, _, _ in
            ValidationOnlyProvider()
        }

        let liveState = app.makeCommandReviewSessionState(
            sessionId: "live-config-session",
            conversationId: nil,
            config: .default
        )
        await ReviewSessionRegistry.shared.register(liveState)
        await app.persistLiveReviewState(liveState, conversationId: nil)

        let command = MCPSharedState.enqueueCodeReviewCommand(
            action: "configure",
            sessionId: "live-config-session",
            conversationId: nil,
            payload: [
                "session_id": "live-config-session",
                "max_workers": "4",
                "analysis_only": "true",
            ]
        )

        await app.processPendingCodeReviewCommandsOnce()

        XCTAssertEqual(try currentCommand(id: command.id)?.status, .completed)
        let snapshot = await liveState.snapshot()
        XCTAssertEqual(snapshot.config.maxWorkers, 4)
        XCTAssertTrue(snapshot.config.analysisOnly)
    }

    func testDeferredReviewMarksCommandFailedWhenSessionFails() async throws {
        let app = makeApp()
        CodeReviewCommandRuntimeHooks.workspaceContextOverride = { [workspaceURL] _ in
            WorkspaceContext(workspacePaths: [workspaceURL].compactMap { $0 })
        }
        CodeReviewCommandRuntimeHooks.providerFactoryOverride = { _, _, _, _, _, sessionState, _ in
            FailingDeferredCodeReviewProvider(
                sessionState: sessionState,
                scopeFiles: ["Sources/File.swift"]
            )
        }

        let command = try MCPSharedState.enqueueUniqueCodeReviewStartCommand(
            sessionId: "review-start-failure",
            conversationId: nil,
            payload: [
                "scope": "uncommitted",
                "session_id": "review-start-failure",
            ]
        )

        await app.processPendingCodeReviewCommandsOnce()
        try await waitForCommand(id: command.id, expectedStatus: .failed)

        let updatedSnapshot = try XCTUnwrap(
            MCPSharedState.readCodeReviewSnapshot(sessionId: "review-start-failure")
        )
        XCTAssertEqual(updatedSnapshot.phase, .failed)
        XCTAssertEqual(try currentCommand(id: command.id)?.status, .failed)
    }

    func testDismissCommandUsesRustPlannerAndPersistsWontFix() async throws {
        let app = makeApp()
        let snapshot = makeSnapshot(
            sessionId: "dismiss-command-session",
            findings: [
                CodeReviewFinding(
                    id: "finding-dismiss",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/File.swift",
                    message: "Dismiss me"
                )
            ]
        )
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let command = MCPSharedState.enqueueCodeReviewCommand(
            action: "dismiss",
            sessionId: snapshot.sessionId,
            conversationId: nil,
            payload: [
                "session_id": snapshot.sessionId,
                "finding_id": "finding-dismiss",
                "reason": "wont_fix",
            ]
        )

        await app.processPendingCodeReviewCommandsOnce()

        XCTAssertEqual(try currentCommand(id: command.id)?.status, .completed)
        let updatedSnapshot = try XCTUnwrap(
            MCPSharedState.readCodeReviewSnapshot(sessionId: snapshot.sessionId)
        )
        XCTAssertEqual(updatedSnapshot.findings.first?.status, .wontFix)
    }

    func testCommentCommandUsesRustMutationAndAppendsComment() async throws {
        let app = makeApp()
        let snapshot = makeSnapshot(
            sessionId: "comment-command-session",
            findings: [
                CodeReviewFinding(
                    id: "finding-comment",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/File.swift",
                    message: "Comment me"
                )
            ]
        )
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let command = MCPSharedState.enqueueCodeReviewCommand(
            action: "comment",
            sessionId: snapshot.sessionId,
            conversationId: nil,
            payload: [
                "session_id": snapshot.sessionId,
                "finding_id": "finding-comment",
                "content": "note from command bus",
            ]
        )

        await app.processPendingCodeReviewCommandsOnce()

        XCTAssertEqual(try currentCommand(id: command.id)?.status, .completed)
        let updatedSnapshot = try XCTUnwrap(
            MCPSharedState.readCodeReviewSnapshot(sessionId: snapshot.sessionId)
        )
        XCTAssertEqual(updatedSnapshot.findings.first?.comments.last?.content, "note from command bus")
    }

    func testAutoPrepareEligibleFindingIdsOnlyReturnsVerifiedFilteredOriginsWithoutExistingPatch() {
        let app = makeApp()
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "review-auto-prepare",
            conversationId: nil,
            phase: .completed,
            stage: .findings,
            findings: [
                CodeReviewFinding(
                    id: "bughunter-verified",
                    severity: .warning,
                    category: .correctness,
                    origin: .bugHunter,
                    filePath: "Sources/Bug.swift",
                    message: "Bug finding",
                    verificationReport: "verified",
                    verifiedAt: Date()
                ),
                CodeReviewFinding(
                    id: "security-prepared",
                    severity: .critical,
                    category: .security,
                    origin: .securityAuditor,
                    filePath: "Sources/Security.swift",
                    message: "Security finding",
                    verificationReport: "verified",
                    verifiedAt: Date(),
                    patchArtifactId: "patch-1"
                ),
                CodeReviewFinding(
                    id: "reviewer-verified",
                    severity: .warning,
                    category: .correctness,
                    origin: .reviewer,
                    filePath: "Sources/Review.swift",
                    message: "Reviewer finding",
                    verificationReport: "verified",
                    verifiedAt: Date()
                ),
                CodeReviewFinding(
                    id: "bughunter-unverified",
                    severity: .warning,
                    category: .correctness,
                    origin: .bugHunter,
                    filePath: "Sources/Pending.swift",
                    message: "Pending finding"
                ),
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: workspaceURL.path,
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            lastUpdatedAt: Date()
        )

        let bugIds = app.autoPrepareEligibleFindingIds(
            snapshot: snapshot,
            originFilter: FindingOrigin.bugHunter.rawValue
        )
        let securityIds = app.autoPrepareEligibleFindingIds(
            snapshot: snapshot,
            originFilter: FindingOrigin.securityAuditor.rawValue
        )
        let allIds = app.autoPrepareEligibleFindingIds(snapshot: snapshot, originFilter: nil)

        XCTAssertEqual(bugIds, ["bughunter-verified"])
        XCTAssertTrue(securityIds.isEmpty)
        XCTAssertEqual(Set(allIds), ["bughunter-verified", "reviewer-verified"])
    }

    private func makeApp() -> CodigoApp {
        let app = CodigoApp()
        return app
    }

    private func makeSnapshot(
        sessionId: String,
        findings: [CodeReviewFinding]
    ) -> CodeReviewSessionSnapshot {
        CodeReviewSessionSnapshot(
            sessionId: sessionId,
            conversationId: nil,
            phase: .fixing,
            stage: .fixing,
            findings: findings,
            events: [],
            config: .default,
            scope: ReviewSessionScope(type: .uncommitted, files: findings.map(\.filePath)),
            workspacePath: workspaceURL.path,
            currentRound: 1,
            activeWorkerCount: 1,
            startedAt: Date(),
            completedAt: nil,
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: "job-1",
            lastTestStatus: nil,
            lastUpdatedAt: Date()
        )
    }

    private func currentCommand(id: String) throws -> MCPSharedCodeReviewCommand? {
        guard let data = try? Data(contentsOf: MCPSharedState.codeReviewCommandsFilePath) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let commands = try decoder.decode([MCPSharedCodeReviewCommand].self, from: data)
        return commands.first(where: { $0.id == id })
    }

    private func waitForCommand(
        id: String,
        expectedStatus: MCPSharedCodeReviewCommand.Status,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if try currentCommand(id: id)?.status == expectedStatus {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for command \(id) to reach \(expectedStatus.rawValue)")
    }
}
