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

    func testPreparePatchPromptIncludesVerificationRemediationAndInvariantContext() {
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

        let prompt = service.preparePatchPrompt(finding: finding, snapshot: snapshot)

        XCTAssertTrue(prompt.contains("Verifica: Riproduzione confermata con retry consecutivo"))
        XCTAssertTrue(prompt.contains("Fix suggerito: Ripristina il guard sullo stato"))
        XCTAssertTrue(prompt.contains("Invariante atteso: Lo stato finale deve essere emesso una sola volta"))
        XCTAssertTrue(prompt.contains("Repro o reasoning: Il retry duplica l'evento terminale"))
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
