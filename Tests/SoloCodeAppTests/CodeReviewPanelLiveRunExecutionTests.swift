import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class CodeReviewPanelLiveRunExecutionTests: XCTestCase {
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

    func testActivatePanelRunSessionSetsSelectionAndRunningState() {
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
