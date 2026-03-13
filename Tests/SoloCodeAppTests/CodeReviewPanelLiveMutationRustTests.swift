import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class CodeReviewPanelLiveMutationRustTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReviewPanelChatSessionStore.shared.clearAll()
    }

    func testLiveDismissUsesRustMutatorAndPersistsSnapshot() async throws {
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

        let sessionState = CodeReviewSessionState(
            sessionId: "live-dismiss-session",
            conversationId: conversationId,
            config: .default
        )
        await sessionState.start(scope: ReviewSessionScope(type: .uncommitted, files: ["Sources/A.swift"]))
        await sessionState.addFinding(
            CodeReviewFinding(
                id: "f-live",
                severity: .warning,
                category: .bug,
                filePath: "Sources/A.swift",
                message: "Dismiss me live"
            )
        )
        await ReviewSessionRegistry.shared.register(sessionState)

        await store.dismissFinding(
            sessionId: "live-dismiss-session",
            findingId: "f-live",
            reason: "wont_fix"
        )

        let liveSnapshotValue = await ReviewSessionRegistry.shared.snapshot(sessionId: "live-dismiss-session")
        let liveSnapshot = try XCTUnwrap(liveSnapshotValue)
        XCTAssertEqual(liveSnapshot.findings.first?.status, .wontFix)
        XCTAssertEqual(liveSnapshot.events.last?.type, .findingDismissed)
        XCTAssertEqual(liveSnapshot.events.last?.metadata["finding_id"], "f-live")

        let persisted = try XCTUnwrap(
            taskStore.codeReviewSnapshot(
                sessionId: "live-dismiss-session",
                conversationId: conversationId
            )
        )
        XCTAssertEqual(persisted.findings.first?.status, .wontFix)
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
