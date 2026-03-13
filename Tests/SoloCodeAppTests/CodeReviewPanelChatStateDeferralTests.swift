import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class CodeReviewPanelChatStateDeferralTests: XCTestCase {
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

    func testSessionStoreEchoDoesNotSynchronouslyRewriteThreadMirror() async {
        let store = makePanelStore()

        store.createNewChatThread(title: "Deferred Mirror")
        await waitUntil("thread mirror becomes available") {
            store.chatThreads.count == 1
        }

        XCTAssertEqual(store.chatThreads.count, 1)
        XCTAssertEqual(store.chatThreads.first?.subtitle, "No messages yet")

        store.appendChatMessage(
            ReviewPanelMessage(role: .user, content: "Mirror me later")
        )

        XCTAssertEqual(store.chatMessages.count, 1)
        XCTAssertEqual(
            store.chatThreads.first?.subtitle,
            "No messages yet",
            "Il mirror dei thread non deve essere riapplicato nello stesso turno del publish locale."
        )

        await waitUntil("thread subtitle gets mirrored") {
            store.chatThreads.first?.subtitle == "Mirror me later"
        }

        XCTAssertEqual(store.chatThreads.first?.subtitle, "Mirror me later")
    }

    func testApplyingIdenticalConversationStateDoesNotRepublishStore() async {
        let store = makePanelStore()

        store.createNewChatThread(title: "Stable Mirror")
        await waitUntil("thread mirror becomes available") {
            store.chatThreads.count == 1
        }

        let mirroredConversation = ReviewPanelChatConversationState(
            threads: store.chatThreads,
            activeThreadId: store.activeChatThreadId
        )
        var publishCount = 0
        let cancellable = store.objectWillChange.sink {
            publishCount += 1
        }
        defer { cancellable.cancel() }

        store.applyChatConversationState(mirroredConversation)

        XCTAssertEqual(
            publishCount,
            0,
            "Riapplicare uno snapshot identico non deve emettere un nuovo publish sul panel store."
        )
    }

    func testSessionStoreEchoOfIdenticalConversationDoesNotRepublishStore() async {
        let conversationId = UUID()
        let store = makePanelStore(conversationId: conversationId)

        store.createNewChatThread(title: "Echo Stable")
        await waitUntil("thread mirror becomes available") {
            store.chatThreads.count == 1
        }

        let sessionKey = CodeReviewPanelStore.chatSessionKey(conversationId: conversationId)
        let mirroredConversation = ReviewPanelChatSessionStore.shared.conversation(for: sessionKey)
        var publishCount = 0
        let cancellable = store.objectWillChange.sink {
            publishCount += 1
        }
        defer { cancellable.cancel() }

        ReviewPanelChatSessionStore.shared.replaceState(
            mirroredConversation.activeThreadId.flatMap { activeId in
                mirroredConversation.threads.first(where: { $0.id == activeId })?.sessionState
            } ?? .empty,
            for: sessionKey
        )
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(
            publishCount,
            0,
            "L'echo identico del session store non deve schedulare un nuovo publish sul panel store."
        )
    }
    func testFinishPanelActionFlushesDeferredReviewRunSections() async throws {
        try requireReviewCore()
        let store = makePanelStore()
        let outputId = store.beginPanelActionOutput(title: "Run review")

        store.handleRawReviewRunEvent(
            id: outputId,
            type: "review-worker-plan",
            payload: ["description": "Late planned work"]
        )
        store.finishPanelActionOutput(id: outputId)
        await drainMainQueue()

        let message = try XCTUnwrap(
            store.chatMessages.first(where: { $0.id == outputId })
        )
        let plannedWork = try XCTUnwrap(
            message.presentation?.sections.first(where: { $0.title == "Planned Work" })
        )
        XCTAssertEqual(plannedWork.lines, ["- [ ] Late planned work"])
    }
    func testFinishPanelActionDoesNotRecreateDeferredResponseBubble() async throws {
        try requireReviewCore()
        let store = makePanelStore()
        let outputId = store.beginPanelActionOutput(title: "Run review")

        store.handleRawReviewRunEvent(
            id: outputId,
            type: "assistant_update",
            payload: ["output": "Late final response"]
        )
        store.finishPanelActionOutput(id: outputId)
        await drainMainQueue()

        let responseMessages = store.chatMessages.filter {
            $0.role == .assistant && $0.kind == .plain
        }
        XCTAssertEqual(responseMessages.count, 1)
        XCTAssertEqual(responseMessages.first?.content, "Late final response")
        XCTAssertFalse(responseMessages.first?.isStreaming ?? true)
    }
    func testAssistantUpdateAfterFinishDoesNotOverwriteFinalizedResponse() async throws {
        try requireReviewCore()
        let store = makePanelStore()
        let outputId = store.beginPanelActionOutput(title: "Run review")

        store.handleRawReviewRunEvent(
            id: outputId,
            type: "assistant_update",
            payload: ["output": "Final response\n---\nFinal verdict"]
        )
        store.finishPanelActionOutput(id: outputId)
        await drainMainQueue()

        store.handleRawReviewRunEvent(
            id: outputId,
            type: "assistant_update",
            payload: ["output": ""]
        )
        await drainMainQueue()

        let plainMessages = store.chatMessages.filter {
            $0.role == .assistant && $0.kind == .plain
        }
        let verdictMessages = store.chatMessages.filter {
            $0.role == .assistant && $0.kind == .reviewRun
        }

        XCTAssertEqual(plainMessages.count, 1)
        XCTAssertEqual(plainMessages.first?.content, "Final response")
        XCTAssertTrue(verdictMessages.contains(where: { $0.content == "Final verdict" }))
    }
    func testTextReplaceAfterFinishDoesNotOverwriteFinalizedResponse() async throws {
        try requireReviewCore()
        let store = makePanelStore()
        let outputId = store.beginPanelActionOutput(title: "Run review")

        store.streamPanelActionOutput(
            id: outputId,
            event: .textReplace("Final response\n---\nFinal verdict")
        )
        store.finishPanelActionOutput(id: outputId)
        await drainMainQueue()

        store.streamPanelActionOutput(
            id: outputId,
            event: .textReplace("Late overwrite")
        )
        await drainMainQueue()

        let plainMessages = store.chatMessages.filter {
            $0.role == .assistant && $0.kind == .plain
        }
        let verdictMessages = store.chatMessages.filter {
            $0.role == .assistant && $0.kind == .reviewRun
        }

        XCTAssertEqual(plainMessages.count, 1)
        XCTAssertEqual(plainMessages.first?.content, "Final response")
        XCTAssertTrue(verdictMessages.contains(where: { $0.content == "Final verdict" }))
        XCTAssertFalse(store.chatMessages.contains(where: { $0.content == "Late overwrite" }))
    }

    func testHandleIncomingChatConversationDefersStateApplication() async {
        let store = makePanelStore()

        store.createNewChatThread(title: "Deferred Apply")
        await waitUntil("thread mirror becomes available") {
            store.chatThreads.count == 1
        }

        let extraThread = ReviewPanelChatThreadState(title: "Extra Thread")
        let newConversation = ReviewPanelChatConversationState(
            threads: store.chatThreads + [extraThread],
            activeThreadId: store.activeChatThreadId
        )
        store.handleIncomingChatConversation(newConversation)
        XCTAssertEqual(
            store.chatThreads.count,
            1,
            "handleIncomingChatConversation must not apply state synchronously."
        )
        XCTAssertNotNil(
            store.pendingChatConversationApplyTask,
            "A deferred task should be scheduled."
        )
        await waitUntil("deferred conversation state is applied") {
            store.chatThreads.count == 2
        }
        XCTAssertEqual(store.chatThreads.count, 2)
        XCTAssertNil(
            store.pendingChatConversationApplyTask,
            "The deferred task should be cleared after execution."
        )
    }

    func testHandleIncomingChatConversationCancelsPreviousDeferredTask() async {
        let store = makePanelStore()

        store.createNewChatThread(title: "Cancel Test")
        await waitUntil("thread mirror becomes available") {
            store.chatThreads.count == 1
        }

        let thread2 = ReviewPanelChatThreadState(title: "Thread 2")
        let thread3 = ReviewPanelChatThreadState(title: "Thread 3")

        let conversation1 = ReviewPanelChatConversationState(
            threads: store.chatThreads + [thread2],
            activeThreadId: store.activeChatThreadId
        )
        let conversation2 = ReviewPanelChatConversationState(
            threads: store.chatThreads + [thread2, thread3],
            activeThreadId: store.activeChatThreadId
        )
        store.handleIncomingChatConversation(conversation1)
        store.handleIncomingChatConversation(conversation2)

        await waitUntil("deferred conversation state is applied") {
            store.chatThreads.count == 3
        }
        XCTAssertEqual(
            store.chatThreads.count,
            3,
            "The last deferred conversation state should win."
        )
    }
    func testTextDeltaAfterFinishDoesNotAppendToFinalizedResponse() async throws {
        try requireReviewCore()
        let store = makePanelStore()
        let outputId = store.beginPanelActionOutput(title: "Run review")

        store.streamPanelActionOutput(
            id: outputId,
            event: .textReplace("Final response")
        )
        store.finishPanelActionOutput(id: outputId)
        await drainMainQueue()

        store.streamPanelActionOutput(
            id: outputId,
            event: .textDelta(" late delta")
        )
        await drainMainQueue()

        let plainMessages = store.chatMessages.filter {
            $0.role == .assistant && $0.kind == .plain
        }
        XCTAssertEqual(plainMessages.count, 1)
        XCTAssertEqual(plainMessages.first?.content, "Final response")
    }

    private func waitUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(description)")
    }

    private func drainMainQueue() async {
        let expectation = expectation(description: "drain main queue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    private func makePanelStore(conversationId: UUID = UUID()) -> CodeReviewPanelStore {
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

    private static func makeProviderFactoryConfig() -> ProviderFactoryConfig {
        ProviderFactoryConfig(openaiApiKey: "", openaiModel: "gpt-4o-mini", anthropicApiKey: "", anthropicModel: "claude-3-5-haiku-latest", googleApiKey: "", googleModel: "gemini-2.0-flash", minimaxApiKey: "", minimaxModel: "MiniMax-M1", openrouterApiKey: "", openrouterModel: "openai/gpt-4o-mini", grokApiKey: "", grokModel: "grok-3-mini", codexPath: "", codexSandbox: "workspace-write", codexSessionFullAccess: false, codexAskForApproval: "never", codexModelOverride: "", codexReasoningEffort: "", codexFastMode: true, codexModelProvider: "", codexPreferResponsesWireAPI: false, planModeBackend: "openai-api", swarmOrchestrator: "openai-api", swarmWorkerBackend: "openai-api", swarmEnabledRoles: "", globalYolo: false, codeReviewPartitions: 2, codeReviewAnalysisOnly: false, codeReviewMaxRounds: 2, codeReviewAnalysisBackend: "openai-api", codeReviewExecutionBackend: "openai-api", claudePath: "", claudeModel: "claude-3-5-sonnet-latest", claudeAllowedTools: [], geminiCliPath: "", geminiModelOverride: "", unifiedToolRuntimeEnabled: true, agentsHardBlockEnabled: true, mcpEditEnforcementEnabled: true, webSearchProvider: "duckduckgo", braveSearchApiKey: "", tavilyApiKey: "", serperApiKey: "")
    }
}
