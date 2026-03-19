import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class CodeReviewPanelChatPromptRoutingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", reviewCoreLibraryPath(), 1)
        ReviewCoreBridge.resetForTests()
    }

    override func tearDown() {
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        ReviewCoreBridge.resetForTests()
        super.tearDown()
    }

    func testNormalizedPanelChatUserMessageKeepsPlainQuestionUntouched() {
        let store = makeStore()

        let normalized = store.normalizedPanelChatUserMessage(
            "Spiegami questo finding.",
            selectedSessionId: "session-1"
        )

        XCTAssertEqual(normalized, "Spiegami questo finding.")
    }

    func testNormalizedPanelChatUserMessagePinsCurrentSessionForReviewRequest() {
        let store = makeStore()

        let normalized = store.normalizedPanelChatUserMessage(
            "Mi fai una review della pipeline del plan panel?",
            selectedSessionId: "session-1"
        )

        XCTAssertTrue(normalized.contains("CURRENT active review session"))
        XCTAssertTrue(normalized.contains("session_id session-1"))
        XCTAssertTrue(normalized.contains("Do NOT call review_start"))
    }

    func testSendChatMessagePinsCurrentSessionBeforeChatProviderFailure() async throws {
        try requireReviewCore()
        let conversationId = UUID()
        let taskStore = TaskActivityStore()
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-pinned",
            conversationId: conversationId,
            phase: .completed,
            stage: .findings,
            findings: [],
            events: [],
            config: .default,
            scope: ReviewSessionScope(type: .workspace, files: ["Sources/App/Main.swift"]),
            workspacePath: nil,
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: nil,
            lastUpdatedAt: Date()
        )
        taskStore.ingestCodeReviewSnapshot(snapshot, conversationId: conversationId)
        let store = makeStore(taskActivityStore: taskStore, conversationId: conversationId)

        await store.sendChatMessage("Spiegami questo finding.")

        XCTAssertEqual(store.panelSessionId, "session-pinned")
    }

    func testSendChatMessageUsesPinnedSessionInPromptWhileSelectionChangesMidStream() async throws {
        try requireReviewCore()
        let conversationId = UUID()
        let taskStore = TaskActivityStore()
        taskStore.ingestCodeReviewSnapshot(
            makeSnapshot(sessionId: "session-a", conversationId: conversationId),
            conversationId: conversationId
        )
        taskStore.ingestCodeReviewSnapshot(
            makeSnapshot(sessionId: "session-b", conversationId: conversationId),
            conversationId: conversationId
        )
        let provider = ControllableReviewPanelProvider(id: "openai-api", displayName: "OpenAI")
        let registry = ProviderRegistry()
        registry.register(provider)
        registry.selectedProviderId = "openai-api"
        let store = makeStore(
            taskActivityStore: taskStore,
            conversationId: conversationId,
            providerRegistry: registry
        )
        store.setSelectedSession("session-a")

        let sendTask = Task {
            await store.sendChatMessage("Mi fai una review della pipeline del plan panel?")
        }

        await waitUntil("chat stream starts") {
            provider.lastPrompt != nil && store.isChatProcessing
        }
        store.setSelectedSession("session-b")
        provider.finish()
        await sendTask.value

        XCTAssertEqual(store.selectedSessionId, "session-b")
        XCTAssertEqual(provider.prompts.count, 1)
        XCTAssertTrue(provider.prompts[0].contains("session_id session-a"))
        XCTAssertFalse(provider.prompts[0].contains("session_id session-b"))
    }

    private func makeStore(
        taskActivityStore: TaskActivityStore? = nil,
        conversationId: UUID? = nil,
        providerRegistry: ProviderRegistry? = nil
    ) -> CodeReviewPanelStore {
        CodeReviewPanelStore(
            taskActivityStore: taskActivityStore ?? TaskActivityStore(),
            providerRegistry: providerRegistry ?? ProviderRegistry(),
            executionController: nil,
            workspaceStore: WorkspaceStore(),
            openFilesStore: OpenFilesStore(),
            conversationId: conversationId,
            providerFactoryConfigBuilder: { Self.makeProviderFactoryConfig() }
        )
    }

    private func makeSnapshot(
        sessionId: String,
        conversationId: UUID
    ) -> CodeReviewSessionSnapshot {
        CodeReviewSessionSnapshot(
            sessionId: sessionId,
            conversationId: conversationId,
            phase: .completed,
            stage: .findings,
            findings: [],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: nil,
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: nil,
            lastUpdatedAt: Date()
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
            claudeModel: "claude-sonnet-4-20250514",
            claudeAllowedTools: [],
            geminiCliPath: "",
            geminiModelOverride: "",
            unifiedToolRuntimeEnabled: true,
            agentsHardBlockEnabled: false,
            mcpEditEnforcementEnabled: false,
            webSearchProvider: "brave",
            braveSearchApiKey: "",
            tavilyApiKey: "",
            serperApiKey: ""
        )
    }

    private func reviewCoreLibraryPath() -> String {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Native/target/debug/libsolocode_rust_core.dylib")
            .path
    }

    private func requireReviewCore() throws {
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Rust review core non disponibile in ambiente.")
        }
    }
}

private final class ControllableReviewPanelProvider: LLMProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    let attachmentCapabilities: ProviderAttachmentCapabilities = .none

    private(set) var prompts: [String] = []
    private var continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation?

    var lastPrompt: String? { prompts.last }

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        prompts.append(prompt)
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
            continuation.yield(.started)
        }
    }

    func finish() {
        continuation?.yield(.completed)
        continuation?.finish()
        continuation = nil
    }
}
