import XCTest
@testable import CoderEngine
@testable import CoderIDE

@MainActor
final class CodeReviewPanelLiveRunExecutionTests: XCTestCase {
    override func tearDown() {
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        ReviewCoreBridge.resetForTests()
        super.tearDown()
    }

    func testPanelRunConversationIdPrefersStoreConversation() {
        let conversationId = UUID()
        let sourceConversationId = UUID()
        let store = makeStore(conversationId: conversationId)

        XCTAssertEqual(
            store.panelRunConversationId(sourceConversationId: sourceConversationId),
            conversationId
        )
    }

    func testPanelRunConversationIdFallsBackToSourceConversation() {
        let sourceConversationId = UUID()
        let store = makeStore(conversationId: nil)

        XCTAssertEqual(
            store.panelRunConversationId(sourceConversationId: sourceConversationId),
            sourceConversationId
        )
    }

    func testActivatePanelRunSessionSetsSelectionAndRunningState() throws {
        try requireReviewCore()
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

        store.activatePanelRunSession(
            sessionId: "panel-run-session",
            conversationId: conversationId
        )

        XCTAssertEqual(store.panelSessionId, "panel-run-session")
        XCTAssertEqual(store.selectedSessionId, "panel-run-session")
        XCTAssertTrue(store.isRunning)
        XCTAssertNotNil(store.runStartedAt)
        XCTAssertNil(store.frozenTimerText)
        XCTAssertNil(store.lastError)
    }

    func testCompletePanelRunAppliesFinishTabAndFreezesTimer() throws {
        try requireReviewCore()
        let store = makeStore(conversationId: nil)
        store.selectedTab = .timeline
        store.isRunning = true
        store.runStartedAt = Date().addingTimeInterval(-5)

        store.completePanelRun(selectTab: .findings)

        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(store.selectedTab, .findings)
        XCTAssertNotNil(store.frozenTimerText)
    }

    func testFailPanelRunAppliesFinishTabAndSetsError() throws {
        try requireReviewCore()
        let store = makeStore(conversationId: nil)
        store.selectedTab = .timeline
        store.isRunning = true
        store.runStartedAt = Date().addingTimeInterval(-5)

        store.failPanelRun(error: "boom", selectTab: .findings)

        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(store.selectedTab, .findings)
        XCTAssertEqual(store.lastError, "boom")
        XCTAssertNotNil(store.frozenTimerText)
    }

    func testActivatePanelRunSessionFailsExplicitlyWhenRustRuntimeDisabled() {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)

        let conversationId = UUID()
        let store = makeStore(conversationId: conversationId)
        store.runPanelReview(
            provider: PanelNoopProvider(),
            prompt: "review",
            context: store.buildWorkspaceContext(),
            sessionState: CodeReviewSessionState(
                sessionId: "runtime-disabled",
                conversationId: conversationId,
                config: .default,
                onStateChange: { _ in }
            ),
            sessionId: "runtime-disabled",
            conversationId: conversationId,
            selectedTabOnStart: .findings,
            selectedTabOnFinish: .findings,
            onEvent: { _ in },
            onComplete: { _ in XCTFail("unexpected completion") },
            onError: { error in
                XCTAssertEqual(error, ReviewPanelStateRustAdapter.runtimeUnavailableMessage)
            }
        )

        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(store.lastError, ReviewPanelStateRustAdapter.runtimeUnavailableMessage)
        XCTAssertEqual(store.selectedTab, .findings)
    }

    private func makeStore(conversationId: UUID?) -> CodeReviewPanelStore {
        CodeReviewPanelStore(
            taskActivityStore: TaskActivityStore(),
            providerRegistry: ProviderRegistry(),
            executionController: nil,
            workspaceStore: WorkspaceStore(),
            openFilesStore: OpenFilesStore(),
            conversationId: conversationId,
            providerFactoryConfigBuilder: { Self.makeProviderFactoryConfig() }
        )
    }

    private static func makeProviderFactoryConfig() -> ProviderFactoryConfig {
        ProviderFactoryConfig(openaiApiKey: "", openaiModel: "gpt-4o-mini", anthropicApiKey: "", anthropicModel: "claude-3-5-haiku-latest", googleApiKey: "", googleModel: "gemini-2.0-flash", minimaxApiKey: "", minimaxModel: "MiniMax-M1", openrouterApiKey: "", openrouterModel: "openai/gpt-4o-mini", grokApiKey: "", grokModel: "grok-3-mini", codexPath: "", codexSandbox: "workspace-write", codexSessionFullAccess: false, codexAskForApproval: "never", codexModelOverride: "", codexReasoningEffort: "", codexFastMode: true, codexModelProvider: "", codexPreferResponsesWireAPI: false, planModeBackend: "openai-api", swarmOrchestrator: "openai-api", swarmWorkerBackend: "openai-api", swarmEnabledRoles: "", globalYolo: false, codeReviewPartitions: 2, codeReviewAnalysisOnly: false, codeReviewMaxRounds: 2, codeReviewAnalysisBackend: "openai-api", codeReviewExecutionBackend: "openai-api", claudePath: "", claudeModel: "claude-3-5-sonnet-latest", claudeAllowedTools: [], geminiCliPath: "", geminiModelOverride: "", unifiedToolRuntimeEnabled: true, agentsHardBlockEnabled: true, mcpEditEnforcementEnabled: true, webSearchProvider: "duckduckgo", braveSearchApiKey: "", tavilyApiKey: "", serperApiKey: "")
    }

    private func requireReviewCore() throws {
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", reviewCoreLibraryPath(from: #filePath), 1)
        ReviewCoreBridge.resetForTests()
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Rust review core non disponibile in ambiente.")
        }
    }
}

private struct PanelNoopProvider: LLMProvider {
    let id = "panel-noop"
    let displayName = "PanelNoop"
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

final class ReviewPipelineNoFilesMessageTests: XCTestCase {
    func testErrorMessageIsReturnedWhenPresent() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "main",
            normalizedInput: "main",
            currentHeadRevision: nil,
            error: "fatal: bad revision 'main'"
        )
        XCTAssertTrue(msg.contains("fatal: bad revision"))
        XCTAssertTrue(msg.contains("main"))
    }

    func testEmptyErrorStringIsIgnored() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "abc123",
            normalizedInput: "abc123^..abc123",
            currentHeadRevision: nil,
            error: ""
        )
        XCTAssertFalse(msg.contains("fatal"))
        XCTAssertTrue(msg.contains("single-commit range"))
    }

    func testNilHeadRevisionDoesNotCrash() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "abc1234",
            normalizedInput: "abc1234^..abc1234",
            currentHeadRevision: nil,
            error: nil
        )
        XCTAssertTrue(msg.contains("single-commit range"))
        XCTAssertFalse(msg.contains("HEAD"))
    }

    func testEmptyHeadRevisionFalselyMatchesRef() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "abc1234",
            normalizedInput: "abc1234^..abc1234",
            currentHeadRevision: "",
            error: nil
        )
        XCTAssertTrue(msg.contains("single-commit range"))
        XCTAssertTrue(msg.contains("current `HEAD` commit"))
    }

    func testSingleCommitWithMatchingHead() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "1e72c30",
            normalizedInput: "1e72c30^..1e72c30",
            currentHeadRevision: "1e72c3016738d6e34ad2b79e0c4a1676ded3e234",
            error: nil
        )
        XCTAssertTrue(msg.contains("current `HEAD` commit"))
        XCTAssertTrue(msg.contains("single-commit range"))
    }

    func testSingleCommitWithoutMatchingHead() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "1e72c30",
            normalizedInput: "1e72c30^..1e72c30",
            currentHeadRevision: "aaaaaaa0000000000000000000000000ffffffff",
            error: nil
        )
        XCTAssertFalse(msg.contains("current `HEAD` commit"))
        XCTAssertTrue(msg.contains("single-commit range"))
    }

    func testRangeRefDoesNotMentionSingleCommit() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "main..feature",
            normalizedInput: "main..feature",
            currentHeadRevision: "abc123",
            error: nil
        )
        XCTAssertFalse(msg.contains("single-commit range"))
        XCTAssertTrue(msg.contains("No changed source files against"))
    }

    func testWhitespaceInRefIsTrimmed() {
        let msg = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "  abc1234  ",
            normalizedInput: "abc1234^..abc1234",
            currentHeadRevision: nil,
            error: nil
        )
        XCTAssertTrue(msg.contains("single-commit range"))
    }
}
