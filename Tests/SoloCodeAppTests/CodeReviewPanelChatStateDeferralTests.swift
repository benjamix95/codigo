import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class CodeReviewPanelChatStateDeferralTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReviewPanelChatSessionStore.shared.clearAll()
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
