import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class ReviewPanelLifecycleE2ETests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReviewPanelChatSessionStore.shared.clearAll()
    }

    override func tearDown() {
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        ReviewCoreBridge.resetForTests()
        super.tearDown()
    }
    func testPanelReviewLifecycleStreamsIntoPanelChatAndPublishesSummary() async throws {
        try requireReviewCore()
        let taskStore = TaskActivityStore()
        let conversationId = UUID()
        let store = makePanelStore(
            taskActivityStore: taskStore,
            conversationId: conversationId
        )
        let sessionId = "panel-e2e-\(UUID().uuidString.prefix(8))"

        let sessionState = CodeReviewSessionState(
            sessionId: sessionId,
            conversationId: conversationId,
            config: .default,
            onStateChange: { [weak store] snapshot in
                Task { @MainActor in
                    await ReviewSessionRegistry.shared.recordSnapshot(snapshot)
                    store?.taskActivityStore.ingestCodeReviewSnapshot(
                        snapshot,
                        conversationId: conversationId
                    )
                    store?.panelSessionId = snapshot.sessionId
                }
            }
        )
        await ReviewSessionRegistry.shared.register(sessionState)

        let provider = PanelLifecycleMockProvider(sessionState: sessionState)
        let prompt = "Run Standard on Uncommitted changes"
        let outputId = store.beginPanelActionOutput(
            title: "Run Standard on Uncommitted changes",
            detail: prompt,
            selectChatTab: true
        )
        store.isRunning = true
        store.runStartedAt = Date()
        store.panelSessionId = sessionId
        taskStore.setSelectedCodeReviewSessionId(sessionId, for: conversationId)
        store.coordinator.runReview(
            provider: provider,
            prompt: prompt,
            context: store.buildWorkspaceContext(),
            sessionState: sessionState,
            onEvent: { [weak store] event in
                store?.streamPanelActionOutput(id: outputId, event: event)
            },
            onStart: { },
            onFinish: { [weak store] result in
                store?.isRunning = false
                if result.wasCancelled {
                    _ = store?.failPanelActionOutput(
                        id: outputId,
                        error: "Review cancelled",
                        runtime: .run,
                        wasCancelled: true
                    )
                } else if let error = result.error {
                    _ = store?.failPanelActionOutput(id: outputId, error: error)
                } else {
                    _ = store?.finishPanelActionOutput(
                        id: outputId,
                        fallbackContent: "Review completed."
                    )
                }
            }
        )
        try await waitUntil("panel review completes") {
            store.isRunning == false
                && taskStore.codeReviewSnapshot(
                    sessionId: sessionId,
                    conversationId: conversationId
                )?.phase == .completed
        }

        XCTAssertEqual(store.selectedTab, .chat)
        XCTAssertEqual(store.panelSessionId, sessionId)
        let commandMessage = try XCTUnwrap(store.chatMessages.first)
        XCTAssertEqual(commandMessage.kind, .commandInvocation)
        let reviewMessage = try XCTUnwrap(
            store.chatMessages.first(where: { $0.id == outputId })
        )
        XCTAssertEqual(reviewMessage.kind, .reviewRun)
        XCTAssertFalse(reviewMessage.isStreaming)
        XCTAssertTrue(reviewMessage.presentation?.sections.map(\.title).contains("Activity") == true)
        XCTAssertFalse(reviewMessage.presentation?.sections.isEmpty ?? true)
        let responseMessage = try XCTUnwrap(
            store.chatMessages.first(where: { $0.role == .assistant && $0.kind == .plain })
        )
        XCTAssertFalse(responseMessage.isStreaming)
        XCTAssertFalse(responseMessage.content.isEmpty)
        let snapshot = try XCTUnwrap(
            taskStore.codeReviewSnapshot(
                sessionId: sessionId,
                conversationId: conversationId
            )
        )
        XCTAssertEqual(snapshot.findings.count, 1)
        XCTAssertEqual(snapshot.phase, .completed)
        XCTAssertFalse(taskStore.swarmCardStates(for: conversationId).isEmpty)
        XCTAssertFalse(store.todoStore?.displayTodosForChat(for: conversationId).isEmpty ?? true)

        store.publishSummaryToChat(sessionId: sessionId)

        let summaryMessage = try XCTUnwrap(
            store.chatMessages.last(where: { $0.kind == .summary })
        )
        XCTAssertEqual(summaryMessage.presentation?.sections.map(\.title), ["Outcome", "Findings"])
        let storedState = ReviewPanelChatSessionStore.shared.state(
            for: CodeReviewPanelStore.chatSessionKey(conversationId: conversationId)
        )
        XCTAssertEqual(storedState.messages, store.chatMessages)
        XCTAssertFalse(storedState.isProcessing)
    }
    func testPanelChatStreamUsesRawToolEventsAndTodoSync() async throws {
        try requireReviewCore()
        let taskStore = TaskActivityStore()
        let conversationId = UUID()
        let providerRegistry = ProviderRegistry()
        providerRegistry.register(PanelChatToolMockProvider())

        let store = CodeReviewPanelStore(
            taskActivityStore: taskStore,
            providerRegistry: providerRegistry,
            executionController: nil,
            workspaceStore: WorkspaceStore(),
            openFilesStore: OpenFilesStore(),
            todoStore: TodoStore(),
            conversationId: conversationId,
            providerFactoryConfigBuilder: { self.makeProviderFactoryConfig() }
        )

        await store.sendChatMessage("analizza i bug")

        try await waitUntil("panel chat stream completes") {
            store.isChatProcessing == false && store.chatMessages.count >= 2
        }
        let reviewRun = try XCTUnwrap(
            store.chatMessages.first(where: { $0.role == .assistant && $0.kind == .reviewRun })
        )
        XCTAssertFalse(reviewRun.isStreaming)
        XCTAssertTrue(reviewRun.presentation?.sections.map(\.title).contains("Activity") == true)
        XCTAssertFalse(reviewRun.presentation?.sections.isEmpty ?? true)
        let response = try XCTUnwrap(
            store.chatMessages.first(where: { $0.role == .assistant && $0.kind == .plain })
        )
        XCTAssertFalse(response.isStreaming)
        XCTAssertFalse(response.content.isEmpty)
        XCTAssertFalse(taskStore.activities.isEmpty)
        XCTAssertFalse(store.todoStore?.displayTodosForChat(for: conversationId).isEmpty ?? true)
    }

    private func makePanelStore(
        taskActivityStore: TaskActivityStore,
        conversationId: UUID?
    ) -> CodeReviewPanelStore {
        CodeReviewPanelStore(
            taskActivityStore: taskActivityStore,
            providerRegistry: ProviderRegistry(),
            executionController: nil,
            workspaceStore: WorkspaceStore(),
            openFilesStore: OpenFilesStore(),
            todoStore: TodoStore(),
            conversationId: conversationId,
            providerFactoryConfigBuilder: { self.makeProviderFactoryConfig() }
        )
    }

    private func waitUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for \(description)")
    }

    private func makeProviderFactoryConfig() -> ProviderFactoryConfig {
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

private final class PanelLifecycleMockProvider: LLMProvider, @unchecked Sendable {
    let id = "panel-lifecycle-mock"
    let displayName = "PanelLifecycleMock"
    let attachmentCapabilities: ProviderAttachmentCapabilities = .none

    private let sessionState: CodeReviewSessionState

    init(sessionState: CodeReviewSessionState) {
        self.sessionState = sessionState
    }

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let sessionState = self.sessionState
        return AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started)
                await sessionState.start(
                    scope: ReviewSessionScope(
                        type: .uncommitted,
                        files: ["Sources/App/Main.swift"]
                    ),
                    workspacePath: context.workspacePath.path
                )
                continuation.yield(.raw(type: "reasoning", payload: [
                    "detail": "Inspecting diff clusters and selecting audit strategy"
                ]))
                continuation.yield(.raw(type: "review-worker-plan", payload: [
                    "worker_id": "worker-1",
                    "description": "Check Main.swift for regressions",
                    "severity": "warning",
                    "fileCount": "1",
                    "files_raw": "Sources/App/Main.swift",
                    "files": "Sources/App/Main.swift",
                ]))
                continuation.yield(.raw(type: "todo_write", payload: [
                    "title": "Check Main.swift for regressions",
                    "status": "in_progress",
                ]))
                continuation.yield(.raw(type: "agent", payload: [
                    "title": "worker-1",
                    "detail": "started",
                    "swarm_id": "worker-1",
                    "group_id": "swarm-worker-1",
                ]))
                continuation.yield(.textDelta("worker-1 started\nworker-1 completed\n"))
                continuation.yield(.raw(type: "agent", payload: [
                    "title": "worker-1",
                    "detail": "completed",
                    "swarm_id": "worker-1",
                    "group_id": "swarm-worker-1",
                ]))
                await sessionState.addFinding(
                    CodeReviewFinding(
                        id: "finding-e2e",
                        severity: .warning,
                        category: .correctness,
                        filePath: "Sources/App/Main.swift",
                        message: "E2E finding"
                    )
                )
                continuation.yield(.textDelta("\n---\n"))
                continuation.yield(
                    .textDelta("**Multi-swarm code review complete.** Tests passing. Re-review clean.\n")
                )
                await sessionState.complete()
                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }
}

private final class PanelChatToolMockProvider: LLMProvider, @unchecked Sendable {
    let id = "panel-chat-tool-mock"
    let displayName = "PanelChatToolMock"
    let attachmentCapabilities: ProviderAttachmentCapabilities = .none

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started)
                continuation.yield(.raw(type: "reasoning", payload: [
                    "detail": "Tracing bug clusters and running audit tools"
                ]))
                continuation.yield(.raw(type: "todo_write", payload: [
                    "title": "Review bug cluster",
                    "status": "in_progress",
                ]))
                continuation.yield(.raw(type: "agent", payload: [
                    "title": "bugHunter",
                    "detail": "started",
                    "swarm_id": "bughunter-chat",
                    "group_id": "swarm-bughunter-chat",
                ]))
                continuation.yield(.textDelta("Ho verificato il cluster principale.\n"))
                continuation.yield(.raw(type: "agent", payload: [
                    "title": "bugHunter",
                    "detail": "completed",
                    "swarm_id": "bughunter-chat",
                    "group_id": "swarm-bughunter-chat",
                ]))
                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }
}
