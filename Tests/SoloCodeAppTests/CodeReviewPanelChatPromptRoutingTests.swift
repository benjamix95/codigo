import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class CodeReviewPanelChatPromptRoutingTests: XCTestCase {
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

    func testSendChatMessagePinsCurrentSessionBeforeChatProviderFailure() async {
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

    private func makeStore(
        taskActivityStore: TaskActivityStore? = nil,
        conversationId: UUID? = nil
    ) -> CodeReviewPanelStore {
        CodeReviewPanelStore(
            taskActivityStore: taskActivityStore ?? TaskActivityStore(),
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
}
