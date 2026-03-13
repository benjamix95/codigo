import XCTest
import CoderEngine
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

    func testCompletePanelRunKeepsChatSelectionAndFreezesTimer() throws {
        try requireReviewCore()
        let store = makeStore(conversationId: nil)
        store.selectedTab = .chat
        store.isRunning = true
        store.runStartedAt = Date().addingTimeInterval(-5)

        store.completePanelRun(selectTab: .findings)

        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(store.selectedTab, .chat)
        XCTAssertNotNil(store.frozenTimerText)
    }

    func testFailPanelRunSetsErrorAndSelection() throws {
        try requireReviewCore()
        let store = makeStore(conversationId: nil)
        store.selectedTab = .chat
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
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", reviewCoreLibraryPath(), 1)
        ReviewCoreBridge.resetForTests()
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Rust review core non disponibile in ambiente.")
        }
    }

    private func reviewCoreLibraryPath() -> String {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Native/target/debug/libsolocode_rust_core.dylib").path
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
