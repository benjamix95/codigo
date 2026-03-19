import XCTest
@testable import CoderIDE
@testable import CoderEngine

@MainActor
final class ReviewPatchWorkflowServiceTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        ReviewCoreBridge.resetForTests()
        VerifiedFindingsPatchExecutionService.resetForTests()
    }

    override func tearDownWithError() throws {
        VerifiedFindingsPatchExecutionService.resetForTests()
        ReviewCoreBridge.resetForTests()
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        try super.tearDownWithError()
    }

    func testPreparePatchPromptIncludesVerificationRemediationAndInvariantContext() throws {
        let service = ReviewPatchWorkflowService()
        let finding = CodeReviewFinding(
            id: "finding-ctx",
            severity: .warning,
            category: .correctness,
            filePath: "Sources/File.swift",
            lineNumber: 42,
            message: "Invariant broken",
            suggestedFix: "Ripristina il guard sullo stato",
            expectedInvariant: "Lo stato finale deve essere emesso una sola volta",
            reproOrReasoning: "Il retry duplica l'evento terminale",
            verificationReport: "Riproduzione confermata con retry consecutivo",
            verifiedAt: Date()
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-ctx",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [finding],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
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

        try requireReviewCore()
        guard ReviewCoreBridge.isEnabled else {
            throw XCTSkip("Rust review core non disponibile in ambiente.")
        }
        let prompt = try service.preparePatchPrompt(finding: finding, snapshot: snapshot)

        XCTAssertTrue(prompt.contains("Verifica: Riproduzione confermata con retry consecutivo"))
        XCTAssertTrue(prompt.contains("Fix suggerito: Ripristina il guard sullo stato"))
        XCTAssertTrue(prompt.contains("Invariante atteso: Lo stato finale deve essere emesso una sola volta"))
        XCTAssertTrue(prompt.contains("Repro o reasoning: Il retry duplica l'evento terminale"))
    }

    func testPreparePatchContextFailsClosedWhenRustPrepareContextUnavailable() {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
        let service = ReviewPatchWorkflowService()
        let finding = CodeReviewFinding(
            id: "finding-ctx",
            severity: .warning,
            category: .correctness,
            filePath: "Sources/File.swift",
            message: "Invariant broken",
            verificationReport: "verified",
            verifiedAt: Date()
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-ctx",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [finding],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
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

        XCTAssertThrowsError(
            try service.preparePatchPrompt(finding: finding, snapshot: snapshot)
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                ReviewPatchWorkflowError
                    .applyFailed("Rust patch prepare context runtime required but unavailable")
                    .localizedDescription
            )
        }
    }

    func testApplyPatchRejectsArtifactThatWasNotVerified() async {
        let service = ReviewPatchWorkflowService()
        let artifact = ReviewPatchArtifact(
            findingId: "finding-1",
            patchText: "diff --git a/File.swift b/File.swift\n",
            diffPreview: "preview",
            touchedFiles: ["File.swift"],
            status: .draft,
            verifyStatus: .pending
        )

        do {
            _ = try await service.applyPatch(artifact: artifact, workspaceRoot: "/tmp")
            XCTFail("Expected patchNotVerified")
        } catch {
            XCTAssertEqual(error as? ReviewPatchWorkflowError, .patchNotVerified)
        }
    }

    func testApplyPatchResultUsesRustBridgeWhenAvailable() throws {
        try requireReviewCore()
        let service = ReviewPatchWorkflowService()
        let artifact = ReviewPatchArtifact(
            id: "patch-apply-1",
            findingId: "finding-1",
            patchText: "diff --git a/File.swift b/File.swift\n",
            diffPreview: "@@",
            touchedFiles: ["File.swift"],
            status: .verified,
            verifyStatus: .verified
        )
        let validation = ValidationRunResult(
            runId: "run-1",
            profile: .reviewPatchApply,
            status: .passed,
            touchedFiles: ["File.swift"],
            stageResults: [],
            durationMs: 10,
            failure: nil
        )

        let updated = try service.applyPatchResult(
            artifact: artifact,
            validation: validation
        )

        XCTAssertEqual(updated.status, .applied)
        XCTAssertEqual(updated.verifyStatus, .verified)
        XCTAssertEqual(updated.validationRunId, "run-1")
        XCTAssertEqual(updated.validationStatus, .passed)
        XCTAssertEqual(updated.rollbackRef, "reverse:patch-apply-1")
    }

    func testApplyPatchResultFailsClosedWhenRustRuntimeUnavailable() {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
        let service = ReviewPatchWorkflowService()
        let artifact = ReviewPatchArtifact(
            id: "patch-apply-2",
            findingId: "finding-2",
            patchText: "diff --git a/File.swift b/File.swift\n",
            diffPreview: "@@",
            touchedFiles: ["File.swift"],
            status: .verified,
            verifyStatus: .verified
        )
        let validation = ValidationRunResult(
            runId: "run-2",
            profile: .reviewPatchApply,
            status: .passed,
            touchedFiles: ["File.swift"],
            stageResults: [],
            durationMs: 10,
            failure: nil
        )

        XCTAssertThrowsError(
            try service.applyPatchResult(
                artifact: artifact,
                validation: validation
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                ReviewPatchWorkflowError
                    .applyFailed("Rust patch apply result runtime required but unavailable")
                    .localizedDescription
            )
        }
    }

    func testVerifyPatchResultUsesRustBridgeWhenAvailable() throws {
        try requireReviewCore()
        let service = ReviewPatchWorkflowService()
        let artifact = ReviewPatchArtifact(
            id: "patch-verify-1",
            findingId: "finding-1",
            patchText: "diff --git a/File.swift b/File.swift\n",
            diffPreview: "@@",
            touchedFiles: ["File.swift"],
            status: .draft,
            verifyStatus: .pending,
            validationStatus: .passed
        )

        let updated = try service.verifyPatchResult(
            artifact: artifact,
            checkPassed: true,
            failureMessage: nil
        )

        XCTAssertEqual(updated.status, .verified)
        XCTAssertEqual(updated.verifyStatus, .verified)
        XCTAssertTrue(updated.conflicts.isEmpty)
    }

    func testVerifyPatchResultFailsClosedWhenRustRuntimeUnavailable() {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
        let service = ReviewPatchWorkflowService()
        let artifact = ReviewPatchArtifact(
            id: "patch-verify-2",
            findingId: "finding-2",
            patchText: "diff --git a/File.swift b/File.swift\n",
            diffPreview: "@@",
            touchedFiles: ["File.swift"],
            status: .draft,
            verifyStatus: .pending,
            validationStatus: .passed
        )

        XCTAssertThrowsError(
            try service.verifyPatchResult(
                artifact: artifact,
                checkPassed: true,
                failureMessage: nil
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                ReviewPatchWorkflowError
                    .applyFailed("Rust patch verify result runtime required but unavailable")
                    .localizedDescription
            )
        }
    }

    func testUpsertingPatchUpdatesFindingStatusAndPatchReference() {
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-1",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-1",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/File.swift",
                    message: "Issue"
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
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
        let artifact = ReviewPatchArtifact(
            id: "patch-1",
            findingId: "finding-1",
            patchText: "diff --git a/File.swift b/File.swift\n",
            diffPreview: "@@",
            touchedFiles: ["Sources/File.swift"],
            status: .applied,
            verifyStatus: .verified
        )

        let updated = VerifiedFindingsService.upsertingPatch(
            in: snapshot,
            artifact: artifact
        )

        XCTAssertEqual(updated.patches.first?.id, "patch-1")
        XCTAssertEqual(updated.findings.first?.patchArtifactId, "patch-1")
        XCTAssertEqual(updated.findings.first?.status, .patchApplied)
    }

    func testCloseFindingExecutionClosesMergedFinding() async throws {
        try requireReviewCore()
        VerifiedFindingsPatchExecutionService.startRuntimeHandler = { _, _, _, _, _ in
            makeReviewPatchRuntimeResponse(
                isError: false,
                runtimeId: "runtime-close-success",
                status: "running",
                currentStep: "close_finding"
            )
        }
        VerifiedFindingsPatchExecutionService.applyRuntimeResultHandler = { _, succeeded, errorMessage in
            makeReviewPatchRuntimeResponse(
                isError: false,
                errorMessage: errorMessage,
                runtimeId: "runtime-close-success",
                status: succeeded ? "completed" : "failed"
            )
        }

        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-close",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-close",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/File.swift",
                    message: "Issue",
                    status: .merged
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
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

        let updated = try await VerifiedFindingsPatchExecutionService.execute(
            action: "close_finding",
            snapshot: snapshot,
            findingId: "finding-close",
            workspaceRoot: "/tmp/repo",
            preferredProviderId: nil,
            providerRegistry: ProviderRegistry()
        )

        XCTAssertEqual(updated.findings.first?.status, .closed)
        XCTAssertEqual(updated.events.last?.type, .outcomePublished)
    }

    func testCloseFindingFailsWhenRustPatchRuntimeIsDisabled() async {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()

        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-close-disabled",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-close",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/File.swift",
                    message: "Issue",
                    status: .merged
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
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

        do {
            _ = try await VerifiedFindingsPatchExecutionService.execute(
                action: "close_finding",
                snapshot: snapshot,
                findingId: "finding-close",
                workspaceRoot: "/tmp/repo",
                preferredProviderId: nil,
                providerRegistry: ProviderRegistry()
            )
            XCTFail("Expected rust patch runtime failure")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                ReviewPatchWorkflowError
                    .applyFailed("Rust patch runtime required but unavailable")
                    .localizedDescription
            )
        }
    }

    func testCloseFindingFailsWhenPatchRuntimeResultBridgeIsUnavailable() async {
        VerifiedFindingsPatchExecutionService.startRuntimeHandler = { _, _, _, _, _ in
            makeReviewPatchRuntimeResponse(
                isError: false,
                runtimeId: "runtime-close-1",
                status: "running",
                currentStep: "close_finding"
            )
        }
        VerifiedFindingsPatchExecutionService.applyRuntimeResultHandler = { _, _, _ in nil }

        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-close-bridge-missing",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-close",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/File.swift",
                    message: "Issue",
                    status: .merged
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
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

        do {
            _ = try await VerifiedFindingsPatchExecutionService.execute(
                action: "close_finding",
                snapshot: snapshot,
                findingId: "finding-close",
                workspaceRoot: "/tmp/repo",
                preferredProviderId: nil,
                providerRegistry: ProviderRegistry()
            )
            XCTFail("Expected runtime result bridge failure")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                ReviewPatchWorkflowError
                    .applyFailed("Rust patch runtime result bridge unavailable")
                    .localizedDescription
            )
        }
    }

    func testPrepareVerifiedPatchesRoutesThroughPatchExecutionRuntime() async throws {
        let expectedPatch = ReviewPatchArtifact(
            id: "patch-finalization-runtime",
            findingId: "finding-finalization",
            patchText: "diff --git a/Authz.swift b/Authz.swift",
            diffPreview: "@@",
            touchedFiles: ["Sources/Authz.swift"],
            status: .verified,
            verifyStatus: .verified
        )
        VerifiedFindingsPatchExecutionService.executeWithProviderHandler = { action, snapshot, findingId, _, _ in
            XCTAssertEqual(action, "prepare_patch")
            XCTAssertEqual(findingId, "finding-finalization")
            let findings = snapshot.findings.map { finding -> CodeReviewFinding in
                guard finding.id == findingId else { return finding }
                var updated = finding
                updated.patchArtifactId = expectedPatch.id
                updated.status = .patchReady
                return updated
            }
            let updated = snapshot.copying(findings: findings, patches: [expectedPatch])
            return updated.copying(outcome: updated.buildOutcomeSummary())
        }

        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-finalization",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-finalization",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/Authz.swift",
                    message: "Prepare me",
                    verificationReport: "verified",
                    verifiedAt: Date()
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
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

        let updated = try await ReviewPatchRuntimeFinalizationService.prepareVerifiedPatches(
            snapshot: snapshot,
            findingIds: ["finding-finalization"],
            workspaceRoot: "/tmp/repo",
            executionProvider: NoopPatchExecutionProvider()
        )

        XCTAssertEqual(updated.patches.map(\.id), [expectedPatch.id])
        XCTAssertEqual(updated.findings.first?.patchArtifactId, expectedPatch.id)
        XCTAssertEqual(updated.findings.first?.status, .patchReady)
    }

    func testPrepareVerifiedPatchesFailsClosedWhenPatchRuntimeIsUnavailable() async {
        VerifiedFindingsPatchExecutionService.executeWithProviderHandler = { _, _, _, _, _ in
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch runtime required but unavailable"
            )
        }

        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-finalization-fail",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-finalization-fail",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/Authz.swift",
                    message: "Prepare me",
                    verificationReport: "verified",
                    verifiedAt: Date()
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
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

        let updated = try? await ReviewPatchRuntimeFinalizationService.prepareVerifiedPatches(
            snapshot: snapshot,
            findingIds: ["finding-finalization-fail"],
            workspaceRoot: "/tmp/repo",
            executionProvider: NoopPatchExecutionProvider()
        )

        XCTAssertEqual(updated?.findings.first?.status, .patchFailed)
        XCTAssertTrue(
            updated?.findings.first?.comments.last?.content
                .contains("Rust patch runtime required but unavailable") == true
        )
    }

    private func requireReviewCore() throws {
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Native/target/debug/libsolocode_rust_core.dylib")
            .path
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", path, 1)
        ReviewCoreBridge.resetForTests()
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Rust review core non disponibile in ambiente.")
        }
    }

}

private struct NoopPatchExecutionProvider: LLMProvider {
    let id = "noop-patch-execution-provider"
    let displayName = "NoopPatchExecutionProvider"
    let attachmentCapabilities: ProviderAttachmentCapabilities = .none

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

@MainActor
final class CodeReviewPanelLiveMutationRustTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReviewPanelChatSessionStore.shared.clearAll()
    }

    func testLiveDismissUsesRustMutatorAndPersistsSnapshot() async throws {
        let taskStore = TaskActivityStore()
        let conversationId = UUID()
        let store = CodeReviewPanelStore(
            taskActivityStore: taskStore,
            providerRegistry: ProviderRegistry(),
            executionController: nil,
            workspaceStore: WorkspaceStore(),
            openFilesStore: OpenFilesStore(),
            conversationId: conversationId,
            providerFactoryConfigBuilder: { Self.makeProviderFactoryConfig() }
        )

        let sessionState = CodeReviewSessionState(
            sessionId: "live-dismiss-session",
            conversationId: conversationId,
            config: .default
        )
        await sessionState.start(scope: ReviewSessionScope(type: .uncommitted, files: ["Sources/A.swift"]))
        await sessionState.addFinding(
            CodeReviewFinding(
                id: "f-live",
                severity: .warning,
                category: .bug,
                filePath: "Sources/A.swift",
                message: "Dismiss me live"
            )
        )
        await ReviewSessionRegistry.shared.register(sessionState)

        await store.dismissFinding(
            sessionId: "live-dismiss-session",
            findingId: "f-live",
            reason: "wont_fix"
        )

        let liveSnapshotValue = await ReviewSessionRegistry.shared.snapshot(sessionId: "live-dismiss-session")
        let liveSnapshot = try XCTUnwrap(liveSnapshotValue)
        XCTAssertEqual(liveSnapshot.findings.first?.status, .wontFix)
        XCTAssertEqual(liveSnapshot.events.last?.type, .findingDismissed)
        XCTAssertEqual(liveSnapshot.events.last?.metadata["finding_id"], "f-live")

        let persisted = try XCTUnwrap(
            taskStore.codeReviewSnapshot(
                sessionId: "live-dismiss-session",
                conversationId: conversationId
            )
        )
        XCTAssertEqual(persisted.findings.first?.status, .wontFix)
    }

    private static func makeProviderFactoryConfig() -> ProviderFactoryConfig {
        ProviderFactoryConfig(
            openaiApiKey: "",
            openaiModel: "gpt-4o-mini",
            anthropicApiKey: "",
            anthropicModel: "claude-3-5-haiku-latest",
            googleApiKey: "",
            googleModel: "gemini-2.0-flash",
            minimaxApiKey: "",
            minimaxModel: "MiniMax-M1",
            openrouterApiKey: "",
            openrouterModel: "openai/gpt-4o-mini",
            grokApiKey: "",
            grokModel: "grok-3-mini",
            codexPath: "",
            codexSandbox: "workspace-write",
            codexSessionFullAccess: false,
            codexAskForApproval: "never",
            codexModelOverride: "",
            codexReasoningEffort: "",
            codexFastMode: true,
            codexModelProvider: "",
            codexPreferResponsesWireAPI: false,
            planModeBackend: "openai-api",
            swarmOrchestrator: "openai-api",
            swarmWorkerBackend: "openai-api",
            swarmEnabledRoles: "",
            globalYolo: false,
            codeReviewPartitions: 2,
            codeReviewAnalysisOnly: false,
            codeReviewMaxRounds: 2,
            codeReviewAnalysisBackend: "openai-api",
            codeReviewExecutionBackend: "openai-api",
            claudePath: "",
            claudeModel: "claude-3-5-sonnet-latest",
            claudeAllowedTools: [],
            geminiCliPath: "",
            geminiModelOverride: "",
            unifiedToolRuntimeEnabled: true,
            agentsHardBlockEnabled: true,
            mcpEditEnforcementEnabled: true,
            webSearchProvider: "duckduckgo",
            braveSearchApiKey: "",
            tavilyApiKey: "",
            serperApiKey: ""
        )
    }
}
