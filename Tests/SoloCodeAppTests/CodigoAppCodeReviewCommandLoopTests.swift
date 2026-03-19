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
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        ReviewCoreBridge.resetForTests()
        CodeReviewCommandRuntimeHooks.providerFactoryOverride = nil
        CodeReviewCommandRuntimeHooks.workspaceContextOverride = nil
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        if let workspaceURL {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        workspaceURL = nil
        try super.tearDownWithError()
    }

    private func requireReviewCore() throws {
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", reviewCoreLibraryPath(), 1)
        ReviewCoreBridge.resetForTests()
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Rust review core non disponibile in ambiente.")
        }
    }

    private func reviewCoreLibraryPath() -> String {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Native/target/debug/libsolocode_rust_core.dylib")
            .path
    }

    func testStartCommandRemainsProcessingUntilDeferredReviewCompletes() async throws {
        try requireReviewCore()
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

    func testStartCommandFailsWhenRustRuntimeIsDisabled() async throws {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()

        let app = makeApp()
        let command = try MCPSharedState.enqueueUniqueCodeReviewStartCommand(
            sessionId: "review-start-disabled",
            conversationId: nil,
            payload: [
                "scope": "uncommitted",
                "session_id": "review-start-disabled",
            ]
        )

        await app.processPendingCodeReviewCommandsOnce()

        XCTAssertEqual(try currentCommand(id: command.id)?.status, .failed)
        XCTAssertNil(
            MCPSharedState.readCodeReviewSnapshot(sessionId: "review-start-disabled")
        )
    }

    func testDeferredReviewFailsWhenRustFinalizationRuntimeBecomesUnavailable() async throws {
        try requireReviewCore()
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
            sessionId: "review-start-finalize-disabled",
            conversationId: nil,
            payload: [
                "scope": "uncommitted",
                "session_id": "review-start-finalize-disabled",
            ]
        )

        await app.processPendingCodeReviewCommandsOnce()

        XCTAssertEqual(try currentCommand(id: command.id)?.status, .processing)
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
        await gate.finishSuccessfully()
        try await waitForCommand(id: command.id, expectedStatus: .failed)

        let snapshot = try XCTUnwrap(
            MCPSharedState.readCodeReviewSnapshot(sessionId: "review-start-finalize-disabled")
        )
        XCTAssertEqual(snapshot.phase, .completed)
        let updatedCommand = try currentCommand(id: command.id)
        XCTAssertEqual(updatedCommand?.status, .failed)
        XCTAssertEqual(
            updatedCommand?.resultMessage,
            "Rust deferred review finalization runtime required but unavailable"
        )
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
        try requireReviewCore()
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

    func testConfigureCommandUpdatesPersistedSnapshotThroughRustMutation() async throws {
        try requireReviewCore()
        let app = makeApp()
        CodeReviewCommandRuntimeHooks.providerFactoryOverride = { _, _, _, _, _, _, _ in
            ValidationOnlyProvider()
        }

        let snapshot = makeSnapshot(
            sessionId: "persisted-config-session",
            findings: []
        )
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let command = MCPSharedState.enqueueCodeReviewCommand(
            action: "configure",
            sessionId: "persisted-config-session",
            conversationId: nil,
            payload: [
                "session_id": "persisted-config-session",
                "max_workers": "5",
                "max_rounds": "4",
                "analysis_only": "true",
            ]
        )

        await app.processPendingCodeReviewCommandsOnce()

        XCTAssertEqual(try currentCommand(id: command.id)?.status, .completed)
        let updatedSnapshot = try XCTUnwrap(
            MCPSharedState.readCodeReviewSnapshot(sessionId: "persisted-config-session")
        )
        XCTAssertEqual(updatedSnapshot.config.maxWorkers, 5)
        XCTAssertEqual(updatedSnapshot.config.maxRounds, 4)
        XCTAssertTrue(updatedSnapshot.config.analysisOnly)
        XCTAssertEqual(updatedSnapshot.events.last?.type, .configUpdated)
    }

    func testConfigureCommandFailsWhenRustMutationRuntimeIsDisabled() async throws {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()

        let app = makeApp()
        CodeReviewCommandRuntimeHooks.providerFactoryOverride = { _, _, _, _, _, _, _ in
            ValidationOnlyProvider()
        }

        let snapshot = makeSnapshot(
            sessionId: "persisted-config-disabled",
            findings: []
        )
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let command = MCPSharedState.enqueueCodeReviewCommand(
            action: "configure",
            sessionId: "persisted-config-disabled",
            conversationId: nil,
            payload: [
                "session_id": "persisted-config-disabled",
                "max_workers": "5",
                "analysis_only": "true",
            ]
        )

        await app.processPendingCodeReviewCommandsOnce()

        XCTAssertEqual(try currentCommand(id: command.id)?.status, .failed)
        let updatedSnapshot = try XCTUnwrap(
            MCPSharedState.readCodeReviewSnapshot(sessionId: "persisted-config-disabled")
        )
        XCTAssertEqual(updatedSnapshot.config.maxWorkers, snapshot.config.maxWorkers)
        XCTAssertEqual(updatedSnapshot.config.analysisOnly, snapshot.config.analysisOnly)
    }

    func testDeferredReviewMarksCommandFailedWhenSessionFails() async throws {
        try requireReviewCore()
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
        try requireReviewCore()
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

    func testDismissCommandFailsWhenRustRuntimeDisabled() async throws {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
        let app = makeApp()
        let snapshot = makeSnapshot(
            sessionId: "dismiss-command-fallback",
            findings: [
                CodeReviewFinding(
                    id: "finding-dismiss-fallback",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/File.swift",
                    message: "Dismiss me locally"
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
                "finding_id": "finding-dismiss-fallback",
                "reason": "wont_fix",
            ]
        )

        await app.processPendingCodeReviewCommandsOnce()

        XCTAssertEqual(try currentCommand(id: command.id)?.status, .failed)
        let updatedSnapshot = try XCTUnwrap(
            MCPSharedState.readCodeReviewSnapshot(sessionId: snapshot.sessionId)
        )
        XCTAssertEqual(updatedSnapshot.findings.first?.status, .open)
    }

    func testCommentCommandUsesRustMutationAndAppendsComment() async throws {
        try requireReviewCore()
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
