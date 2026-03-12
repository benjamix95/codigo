import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class ReviewPanelProviderSelectionTests: XCTestCase {
    func testPanelProviderDefaultsToSelectedAgentProviderAndCanOverride() {
        let registry = ProviderRegistry()
        registry.register(MockReviewPanelProvider(id: "openai-api", displayName: "OpenAI"))
        registry.register(MockReviewPanelProvider(id: "claude-cli", displayName: "Claude CLI"))
        registry.selectedProviderId = "openai-api"

        let store = CodeReviewPanelStore(
            taskActivityStore: TaskActivityStore(),
            providerRegistry: registry,
            executionController: nil,
            workspaceStore: WorkspaceStore(),
            openFilesStore: OpenFilesStore(),
            conversationId: nil,
            providerFactoryConfigBuilder: { Self.makeProviderFactoryConfig() }
        )

        XCTAssertTrue(store.usesAutomaticProviderSelection)
        XCTAssertEqual(store.effectivePanelProviderId, "openai-api")
        XCTAssertEqual(store.effectivePanelProviderLabel, "gpt-4o-mini")

        store.setPanelProviderOverride("claude-cli")

        XCTAssertFalse(store.usesAutomaticProviderSelection)
        XCTAssertEqual(store.effectivePanelProviderId, "claude-cli")
        XCTAssertEqual(store.effectivePanelProviderLabel, "claude-3-5-sonnet-latest")

        store.setPanelProviderOverride(nil)

        XCTAssertTrue(store.usesAutomaticProviderSelection)
        XCTAssertEqual(store.effectivePanelProviderId, "openai-api")
    }

    func testPanelDefaultsToFindingsTabAndUnifiedModes() {
        let registry = ProviderRegistry()
        registry.register(MockReviewPanelProvider(id: "openai-api", displayName: "OpenAI"))
        registry.selectedProviderId = "openai-api"

        let store = CodeReviewPanelStore(
            taskActivityStore: TaskActivityStore(),
            providerRegistry: registry,
            executionController: nil,
            workspaceStore: WorkspaceStore(),
            openFilesStore: OpenFilesStore(),
            conversationId: nil,
            providerFactoryConfigBuilder: { Self.makeProviderFactoryConfig() }
        )

        XCTAssertEqual(store.selectedTab, .findings)
        XCTAssertEqual(store.selectedModes, [.standard, .bugFinder, .securityAudit])
    }

    func testPublishedFindingsRemainHiddenUntilPatchPreviewIsReady() {
        let registry = ProviderRegistry()
        registry.register(MockReviewPanelProvider(id: "openai-api", displayName: "OpenAI"))
        registry.selectedProviderId = "openai-api"
        let taskStore = TaskActivityStore()
        let conversationId = UUID()
        let store = CodeReviewPanelStore(
            taskActivityStore: taskStore,
            providerRegistry: registry,
            executionController: nil,
            workspaceStore: WorkspaceStore(),
            openFilesStore: OpenFilesStore(),
            conversationId: conversationId,
            providerFactoryConfigBuilder: { Self.makeProviderFactoryConfig() }
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-hidden",
            conversationId: conversationId,
            phase: .analyzing,
            stage: .findings,
            findings: [
                CodeReviewFinding(
                    id: "finding-hidden",
                    severity: .warning,
                    category: .correctness,
                    origin: .bugHunter,
                    filePath: "Sources/App/Main.swift",
                    message: "Terminal event can be emitted twice",
                    verificationReport: "Retry riproduce il doppio terminal event",
                    verifiedAt: Date()
                )
            ],
            events: [],
            config: .default,
            scope: ReviewSessionScope(type: .uncommitted, files: ["Sources/App/Main.swift"]),
            workspacePath: "/tmp/repo",
            currentRound: 0,
            activeWorkerCount: 1,
            startedAt: Date(),
            completedAt: nil,
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: "job-hidden",
            lastTestStatus: nil,
            lastUpdatedAt: Date()
        )

        taskStore.ingestCodeReviewSnapshot(snapshot, conversationId: conversationId)
        store.panelSessionId = snapshot.sessionId

        XCTAssertTrue(store.currentPublishedFindings.isEmpty)
        XCTAssertEqual(store.currentPipelineJobState?.hiddenFindingCount, 1)
        XCTAssertEqual(store.currentPipelineJobState?.phase, "patch_preparation")
    }

    func testPublishedFindingsAppearWhenPatchPreviewIsVerified() {
        let registry = ProviderRegistry()
        registry.register(MockReviewPanelProvider(id: "openai-api", displayName: "OpenAI"))
        registry.selectedProviderId = "openai-api"
        let taskStore = TaskActivityStore()
        let conversationId = UUID()
        let store = CodeReviewPanelStore(
            taskActivityStore: taskStore,
            providerRegistry: registry,
            executionController: nil,
            workspaceStore: WorkspaceStore(),
            openFilesStore: OpenFilesStore(),
            conversationId: conversationId,
            providerFactoryConfigBuilder: { Self.makeProviderFactoryConfig() }
        )
        let patch = ReviewPatchArtifact(
            id: "patch-ready",
            findingId: "finding-ready",
            patchText: "diff --git a/Authz.swift b/Authz.swift",
            diffPreview: "@@",
            touchedFiles: ["Sources/Auth/Authz.swift"],
            status: .verified,
            verifyStatus: .verified
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-ready",
            conversationId: conversationId,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-ready",
                    severity: .warning,
                    category: .security,
                    origin: .securityAuditor,
                    filePath: "Sources/Auth/Authz.swift",
                    lineNumber: 21,
                    message: "Missing authorization guard",
                    status: .patchReady,
                    verificationReport: "Verified on the direct authorization path",
                    verifiedAt: Date(),
                    patchArtifactId: "patch-ready"
                )
            ],
            patches: [patch],
            events: [],
            config: .default,
            scope: ReviewSessionScope(type: .uncommitted, files: ["Sources/Auth/Authz.swift"]),
            workspacePath: "/tmp/repo",
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: "job-ready",
            lastTestStatus: .passed,
            lastUpdatedAt: Date()
        )

        taskStore.ingestCodeReviewSnapshot(snapshot, conversationId: conversationId)
        store.panelSessionId = snapshot.sessionId

        XCTAssertEqual(store.currentPublishedFindings.map(\.id), ["finding-ready"])
        XCTAssertEqual(store.currentPipelineJobState?.publishedFindingCount, 1)
        XCTAssertEqual(store.currentPipelineJobState?.phase, "completed")
    }

    func testVerifiedFindingsStayVisibleBeforePatchPreparationCompletes() {
        let registry = ProviderRegistry()
        registry.register(MockReviewPanelProvider(id: "openai-api", displayName: "OpenAI"))
        registry.selectedProviderId = "openai-api"
        let taskStore = TaskActivityStore()
        let conversationId = UUID()
        let store = CodeReviewPanelStore(
            taskActivityStore: taskStore,
            providerRegistry: registry,
            executionController: nil,
            workspaceStore: WorkspaceStore(),
            openFilesStore: OpenFilesStore(),
            conversationId: conversationId,
            providerFactoryConfigBuilder: { Self.makeProviderFactoryConfig() }
        )
        let baseSnapshot = CodeReviewSessionSnapshot(
            sessionId: "session-progressive",
            conversationId: conversationId,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-progressive",
                    severity: .warning,
                    category: .correctness,
                    origin: .bugHunter,
                    filePath: "Sources/App/Main.swift",
                    message: "Terminal event can be emitted twice",
                    verificationReport: "Retry riproduce il doppio terminal event",
                    verifiedAt: Date()
                )
            ],
            events: [],
            config: .default,
            scope: ReviewSessionScope(type: .uncommitted, files: ["Sources/App/Main.swift"]),
            workspacePath: "/tmp/repo",
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: "job-progressive",
            lastTestStatus: .passed,
            lastUpdatedAt: Date()
        )
        let snapshot = baseSnapshot.copying(
            mutationSequence: baseSnapshot.mutationSequence,
            verifiedFindings: VerifiedFindingsSessionSyncService.sync(snapshot: baseSnapshot),
            lastUpdatedAt: baseSnapshot.lastUpdatedAt
        )

        taskStore.ingestCodeReviewSnapshot(snapshot, conversationId: conversationId)
        store.panelSessionId = snapshot.sessionId

        XCTAssertEqual(store.currentVerifiedFindings.map(\.id), ["finding-progressive"])
        XCTAssertTrue(store.currentPublishedFindings.isEmpty)
        XCTAssertEqual(store.currentVisibleFindings.map(\.id), ["finding-progressive"])
        XCTAssertEqual(store.currentPipelineJobState?.verifiedCount, 1)
    }

    func testCompletedReviewFinalizationAutoPreparesPatchForVerifiedFindings() async throws {
        let registry = ProviderRegistry()
        registry.register(MockReviewPanelProvider(id: "openai-api", displayName: "OpenAI"))
        registry.selectedProviderId = "openai-api"
        let taskStore = TaskActivityStore()
        let conversationId = UUID()
        let workspaceStore = WorkspaceStore()
        workspaceStore.workspaces = [Workspace(name: "Repo", rootPath: "/tmp/repo")]
        workspaceStore.activeWorkspaceId = workspaceStore.workspaces.first?.id
        let store = CodeReviewPanelStore(
            taskActivityStore: taskStore,
            providerRegistry: registry,
            executionController: nil,
            workspaceStore: workspaceStore,
            openFilesStore: OpenFilesStore(),
            conversationId: conversationId,
            providerFactoryConfigBuilder: { Self.makeProviderFactoryConfig() }
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-auto-prepare",
            conversationId: conversationId,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-auto-prepare",
                    severity: .warning,
                    category: .security,
                    origin: .securityAuditor,
                    filePath: "Sources/Auth/Authz.swift",
                    message: "Missing authorization guard",
                    verificationReport: "Verified on the direct authorization path",
                    verifiedAt: Date()
                )
            ],
            events: [],
            config: .default,
            scope: ReviewSessionScope(type: .uncommitted, files: ["Sources/Auth/Authz.swift"]),
            workspacePath: "/tmp/repo",
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: "job-auto-prepare",
            lastTestStatus: .passed,
            lastUpdatedAt: Date()
        )

        ReviewPatchRuntimeFinalizationService.prepareHandler = { currentSnapshot, findingIds, _, _ in
            XCTAssertEqual(findingIds, ["finding-auto-prepare"])
            let patch = ReviewPatchArtifact(
                id: "patch-auto-prepare",
                findingId: "finding-auto-prepare",
                patchText: "diff --git a/Authz.swift b/Authz.swift",
                diffPreview: "@@",
                touchedFiles: ["Sources/Auth/Authz.swift"],
                status: .verified,
                verifyStatus: .verified
            )
            let findings = currentSnapshot.findings.map { finding -> CodeReviewFinding in
                guard finding.id == "finding-auto-prepare" else { return finding }
                var updated = finding
                updated.patchArtifactId = patch.id
                updated.status = .patchReady
                return updated
            }
            let updated = currentSnapshot.copying(findings: findings, patches: [patch])
            return updated.copying(outcome: updated.buildOutcomeSummary())
        }
        defer { ReviewPatchRuntimeFinalizationService.resetForTests() }

        let finalized = await store.finalizeCompletedReviewSessionIfNeeded(snapshot: snapshot)

        XCTAssertEqual(finalized.patches.map(\.id), ["patch-auto-prepare"])
        XCTAssertEqual(finalized.findings.first?.patchArtifactId, "patch-auto-prepare")
        XCTAssertEqual(finalized.findings.first?.status, .patchReady)
    }

    func testPatchFinalizationTargetsUseRustReducer() throws {
        let registry = ProviderRegistry()
        registry.register(MockReviewPanelProvider(id: "openai-api", displayName: "OpenAI"))
        registry.selectedProviderId = "openai-api"
        let store = CodeReviewPanelStore(
            taskActivityStore: TaskActivityStore(),
            providerRegistry: registry,
            executionController: nil,
            workspaceStore: WorkspaceStore(),
            openFilesStore: OpenFilesStore(),
            conversationId: nil,
            providerFactoryConfigBuilder: { Self.makeProviderFactoryConfig() }
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "review-finalization-targets",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-open",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/Authz.swift",
                    message: "Needs patch preview",
                    verificationReport: "verified",
                    verifiedAt: Date()
                ),
                CodeReviewFinding(
                    id: "finding-ready",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/Authz.swift",
                    message: "Already prepared",
                    verificationReport: "verified",
                    verifiedAt: Date(),
                    patchArtifactId: "patch-ready"
                )
            ],
            patches: [
                ReviewPatchArtifact(
                    id: "patch-ready",
                    findingId: "finding-ready",
                    patchText: "diff",
                    diffPreview: "@@",
                    touchedFiles: ["Sources/Authz.swift"],
                    status: .verified,
                    verifyStatus: .verified
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: "job-targets",
            lastTestStatus: .passed,
            lastUpdatedAt: Date()
        )

        XCTAssertEqual(store.patchFinalizationTargets(for: snapshot), ["finding-open"])
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

private struct MockReviewPanelProvider: LLMProvider {
    let id: String
    let displayName: String
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
