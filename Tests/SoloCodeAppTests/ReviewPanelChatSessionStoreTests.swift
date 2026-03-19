import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class ReviewPanelChatSessionStoreTests: XCTestCase {
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

    func testCreateSelectArchiveDeleteThreadLifecycle() {
        let key = "panel-chat-tests"
        let store = ReviewPanelChatSessionStore.shared

        let first = store.createThread(for: key, title: "First")
        store.appendMessage(
            ReviewPanelMessage(role: .user, content: "Hello there"),
            for: key
        )
        let second = store.createThread(for: key, title: "Second")
        store.appendMessage(
            ReviewPanelMessage(role: .assistant, content: "Another thread"),
            for: key
        )

        var conversation = store.conversation(for: key)
        XCTAssertEqual(conversation.activeThreadId, second)
        XCTAssertEqual(conversation.threads.count, 2)

        store.selectThread(first, for: key)
        conversation = store.conversation(for: key)
        XCTAssertEqual(conversation.activeThreadId, first)

        store.archiveThread(first, for: key)
        conversation = store.conversation(for: key)
        XCTAssertTrue(conversation.threads.first(where: { $0.id == first })?.archived == true)
        XCTAssertEqual(conversation.activeThreadId, second)

        store.restoreThread(first, for: key)
        conversation = store.conversation(for: key)
        XCTAssertFalse(conversation.threads.first(where: { $0.id == first })?.archived == true)

        store.deleteThread(second, for: key)
        conversation = store.conversation(for: key)
        XCTAssertEqual(conversation.threads.count, 1)
        XCTAssertEqual(conversation.threads.first?.id, first)
    }

    func testThreadSubtitleShowsLiveWhenProcessing() {
        let key = "panel-chat-live"
        let store = ReviewPanelChatSessionStore.shared

        _ = store.createThread(for: key, title: "Live Chat")
        store.setProcessing(true, startedAt: Date(), for: key)

        let conversation = store.conversation(for: key)
        XCTAssertEqual(conversation.threads.first?.subtitle, "Live")
    }

    func testCreateThreadUsesProvidedTitleAndSelectsIt() {
        let key = "panel-chat-custom-title"
        let store = ReviewPanelChatSessionStore.shared

        let threadId = store.createThread(for: key, title: "panel-123")
        let conversation = store.conversation(for: key)

        XCTAssertEqual(conversation.activeThreadId, threadId)
        XCTAssertEqual(conversation.threads.first?.title, "panel-123")
    }

    func testPanelModeSelectionSupportsUnifiedDefaultsAndReselection() {
        let store = makePanelStore(conversationId: nil)

        XCTAssertEqual(store.selectedModes, [.standard, .bugFinder, .securityAudit])

        store.toggleModeSelection(.securityAudit)

        XCTAssertTrue(store.hasSelectedMode(.standard))
        XCTAssertFalse(store.hasSelectedMode(.securityAudit))
        XCTAssertTrue(store.hasSelectedMode(.bugFinder))

        store.toggleModeSelection(.securityAudit)

        XCTAssertTrue(store.hasSelectedMode(.securityAudit))
    }

    func testPanelCreateAndSelectChatThreadActivatesChatTab() async throws {
        let conversationId = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let store = makePanelStore(conversationId: conversationId)

        store.createNewChatThread(title: "Investigazione")
        let createdThreadId = try XCTUnwrap(store.activeChatThreadId)
        await waitUntil("created thread mirror becomes available") {
            store.chatThreads.first?.title == "Investigazione"
        }

        XCTAssertEqual(store.selectedTab, .chat)
        XCTAssertEqual(store.chatThreads.first?.title, "Investigazione")
        XCTAssertEqual(store.activeChatThreadId, createdThreadId)

        let secondThreadId = ReviewPanelChatSessionStore.shared.createThread(
            for: CodeReviewPanelStore.chatSessionKey(conversationId: conversationId),
            title: "Secondaria"
        )

        store.selectTab(.findings)
        store.selectChatThread(secondThreadId)
        await waitUntil("selected thread mirror becomes active") {
            store.activeChatThreadId == secondThreadId
        }

        XCTAssertEqual(store.selectedTab, .chat)
        XCTAssertEqual(store.activeChatThreadId, secondThreadId)
    }

    func testPanelCreateAndSelectChatThreadSyncsRuntimeSnapshotWhenRustAvailable() async throws {
        try requireReviewCore()
        let conversationId = UUID()
        let store = makePanelStore(conversationId: conversationId)

        store.createNewChatThread(title: "Runtime Backed")
        let createdThreadId = try XCTUnwrap(store.activeChatThreadId)
        await waitUntil("runtime snapshot reflects created active thread") {
            store.makeRuntimeStateSnapshot().activeChatThreadId == createdThreadId
        }

        let secondThreadId = ReviewPanelChatSessionStore.shared.createThread(
            for: CodeReviewPanelStore.chatSessionKey(conversationId: conversationId),
            title: "Runtime Second"
        )
        store.selectChatThread(secondThreadId)
        await waitUntil("runtime snapshot reflects selected active thread") {
            store.makeRuntimeStateSnapshot().activeChatThreadId == secondThreadId
        }

        XCTAssertEqual(store.makeRuntimeStateSnapshot().activeChatThreadId, secondThreadId)
    }

    func testPanelCreateAndSelectChatThreadFallsBackLocallyWhenRustUnavailable() async throws {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()

        let conversationId = UUID()
        let store = makePanelStore(conversationId: conversationId)

        store.createNewChatThread(title: "Fallback Thread")
        let createdThreadId = try XCTUnwrap(store.activeChatThreadId)
        await waitUntil("fallback local created thread becomes active") {
            store.activeChatThreadId == createdThreadId
        }

        let secondThreadId = ReviewPanelChatSessionStore.shared.createThread(
            for: CodeReviewPanelStore.chatSessionKey(conversationId: conversationId),
            title: "Fallback Second"
        )
        store.selectChatThread(secondThreadId)
        await waitUntil("fallback local selected thread becomes active") {
            store.activeChatThreadId == secondThreadId
        }

        XCTAssertEqual(store.selectedTab, .chat)
        XCTAssertEqual(store.activeChatThreadId, secondThreadId)
    }

    private func makePanelStore(conversationId: UUID?) -> CodeReviewPanelStore {
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

    private func waitUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollNanoseconds: UInt64 = 20_000_000,
        predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !predicate() {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                XCTFail("Timed out waiting for \(description)")
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }
}
