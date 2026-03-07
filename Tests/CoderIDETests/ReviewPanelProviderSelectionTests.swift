import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class ReviewPanelProviderSelectionTests: XCTestCase {
    func testPanelProviderDefaultsToSelectedAgentProviderAndCanOverride() {
        let registry = ProviderRegistry()
        registry.register(MockReviewPanelProvider(id: "openai-api", displayName: "OpenAI"))
        registry.register(MockReviewPanelProvider(id: "claude-cli", displayName: "Claude CLI"))
        registry.selectedProviderId = "openai-api"

        let store = CodeReviewPanelStore(
            taskActivityStore: TaskActivityStore(),
            providerRegistry: registry,
            executionController: nil,
            workspaceStore: WorkspaceStore(),
            openFilesStore: OpenFilesStore(),
            conversationId: nil,
            providerFactoryConfigBuilder: { Self.makeProviderFactoryConfig() }
        )

        XCTAssertTrue(store.usesAutomaticProviderSelection)
        XCTAssertEqual(store.effectivePanelProviderId, "openai-api")
        XCTAssertEqual(store.effectivePanelProviderLabel, "gpt-4o-mini")

        store.setPanelProviderOverride("claude-cli")

        XCTAssertFalse(store.usesAutomaticProviderSelection)
        XCTAssertEqual(store.effectivePanelProviderId, "claude-cli")
        XCTAssertEqual(store.effectivePanelProviderLabel, "claude-3-5-sonnet-latest")

        store.setPanelProviderOverride(nil)

        XCTAssertTrue(store.usesAutomaticProviderSelection)
        XCTAssertEqual(store.effectivePanelProviderId, "openai-api")
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

private struct MockReviewPanelProvider: LLMProvider {
    let id: String
    let displayName: String
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
