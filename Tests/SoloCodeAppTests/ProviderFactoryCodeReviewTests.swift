import XCTest
import CoderEngine
@testable import CoderIDE

final class ProviderFactoryCodeReviewTests: XCTestCase {
    func testCodeReviewEnabledPhasesUsesSessionAnalysisOnlyOverride() {
        let analysisOnlyConfig = SessionConfig(analysisOnly: true)
        let executionConfig = SessionConfig(analysisOnly: false)

        XCTAssertEqual(
            ProviderFactory.codeReviewEnabledPhases(sessionConfig: analysisOnlyConfig),
            .analysisOnly
        )
        XCTAssertEqual(
            ProviderFactory.codeReviewEnabledPhases(sessionConfig: executionConfig),
            .analysisAndExecution
        )
    }

    func testCodeReviewProviderAnalysisOnlyDoesNotRequireExecutionBackend() {
        var config = makeConfig()
        config.codeReviewAnalysisBackend = "openai-api"
        config.codeReviewExecutionBackend = "google-api"
        config.openaiApiKey = "openai-test-key"
        config.googleApiKey = ""

        let provider = ProviderFactory.codeReviewMultiSwarmProvider(
            config: config,
            executionController: nil,
            agentProviderId: nil,
            workspacePaths: [],
            initialSessionConfig: SessionConfig(
                analysisBackend: "openai-api",
                executionBackend: "google-api",
                analysisOnly: true
            )
        )

        XCTAssertNotNil(provider)
    }

    func testCodeReviewProviderExecutionModeStillRequiresExecutionBackend() {
        var config = makeConfig()
        config.codeReviewAnalysisBackend = "openai-api"
        config.codeReviewExecutionBackend = "google-api"
        config.openaiApiKey = "openai-test-key"
        config.googleApiKey = ""

        let provider = ProviderFactory.codeReviewMultiSwarmProvider(
            config: config,
            executionController: nil,
            agentProviderId: nil,
            workspacePaths: [],
            initialSessionConfig: SessionConfig(
                analysisBackend: "openai-api",
                executionBackend: "google-api",
                analysisOnly: false
            )
        )

        XCTAssertNil(provider)
    }

    private func makeConfig() -> ProviderFactoryConfig {
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
            codeReviewExecutionBackend: "google-api",
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
