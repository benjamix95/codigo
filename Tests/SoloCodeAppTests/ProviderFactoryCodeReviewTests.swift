import XCTest
import Testing
import CoderEngine
@testable import CoderIDE

@MainActor
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

    func testAutoCodeReviewRequestLeavesRegularPromptUntouched() {
        let request = makeAutoCodeReviewRequest(
            userText: "Spiegami questa funzione async.",
            coderMode: .agent
        )

        XCTAssertEqual(request.prompt, "Spiegami questa funzione async.")
        XCTAssertEqual(request.selectedModes, [])
        XCTAssertFalse(request.prefersCodeReviewRuntimeProvider)
    }

    func testAutoCodeReviewRequestWrapsSecurityReviewPrompt() {
        let request = makeAutoCodeReviewRequest(
            userText: "Fai una review di sicurezza del diff e cerca vulnerabilità authz.",
            coderMode: .agent
        )

        XCTAssertTrue(request.prefersCodeReviewRuntimeProvider)
        XCTAssertEqual(request.selectedModes, [.standard, .securityAudit, .bugFinder])
        XCTAssertTrue(request.prompt.contains("[REVIEW_SCOPE:uncommitted]"))
        XCTAssertTrue(request.prompt.contains("Security focus:"))
        XCTAssertTrue(request.prompt.contains("Additional instructions:"))
    }

    func testAutoCodeReviewRequestUsesWorkspaceScopeForArchitecturalReview() {
        let request = makeAutoCodeReviewRequest(
            userText: "Mi fai una review della pipeline del plan panel?",
            coderMode: .agent
        )

        XCTAssertTrue(request.prefersCodeReviewRuntimeProvider)
        XCTAssertEqual(request.selectedModes, [.standard, .securityAudit, .bugFinder])
        XCTAssertTrue(request.prompt.contains("[REVIEW_SCOPE:workspace]"))
    }

    func testAutoCodeReviewRequestWrapsBugHuntPrompt() {
        let request = makeAutoCodeReviewRequest(
            userText: "Fai bug hunt su queste modifiche e cerca regressioni o crash.",
            coderMode: .agent
        )

        XCTAssertTrue(request.prefersCodeReviewRuntimeProvider)
        XCTAssertEqual(request.selectedModes, [.standard, .securityAudit, .bugFinder])
        XCTAssertTrue(request.prompt.contains("Bug focus:"))
    }

    func testAutoCodeReviewRequestSkipsSlashCommands() {
        let request = makeAutoCodeReviewRequest(
            userText: "/fast\n\nFai una review",
            coderMode: .agent
        )

        XCTAssertEqual(request.prompt, "/fast\n\nFai una review")
        XCTAssertEqual(request.selectedModes, [])
        XCTAssertFalse(request.prefersCodeReviewRuntimeProvider)
    }

    func testAutoCodeReviewRequestMatchesVagueSecurityDiffPrompt() {
        let request = makeAutoCodeReviewRequest(
            userText: "Controlla queste modifiche e dimmi se ci sono vulnerabilità o secret esposti.",
            coderMode: .agent
        )

        XCTAssertTrue(request.prefersCodeReviewRuntimeProvider)
        XCTAssertEqual(request.selectedModes, [.standard, .securityAudit, .bugFinder])
        XCTAssertTrue(request.prompt.contains("Security focus:"))
    }

    func testAutoCodeReviewRequestMatchesRegressionPromptWithoutReviewKeyword() {
        let request = makeAutoCodeReviewRequest(
            userText: "Analizza queste modifiche e dimmi se vedi regressioni o crash.",
            coderMode: .agent
        )

        XCTAssertTrue(request.prefersCodeReviewRuntimeProvider)
        XCTAssertEqual(request.selectedModes, [.standard, .securityAudit, .bugFinder])
        XCTAssertTrue(request.prompt.contains("Bug focus:"))
    }

    func testAutoCodeReviewRequestDoesNotHijackGenericExplanationPrompt() {
        let request = makeAutoCodeReviewRequest(
            userText: "Spiegami come funziona la policy di sicurezza del progetto.",
            coderMode: .agent
        )

        XCTAssertEqual(request.prompt, "Spiegami come funziona la policy di sicurezza del progetto.")
        XCTAssertEqual(request.selectedModes, [])
        XCTAssertFalse(request.prefersCodeReviewRuntimeProvider)
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

struct RuntimeResourceLocatorTests {
    @Test
    func appLogoLookupReturnsExistingFileWhenFound() {
        let logoURL = RuntimeResourceLocator.appLogoURL()
        guard let logoURL else { return }

        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: logoURL.path, isDirectory: &isDirectory)
        #expect(exists)
        #expect(!isDirectory.boolValue)
    }

    @Test
    func fontsDirectoryLookupReturnsDirectoryWhenFound() {
        let fontsURL = RuntimeResourceLocator.fontsDirectoryURL()
        guard let fontsURL else { return }

        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: fontsURL.path, isDirectory: &isDirectory)
        #expect(exists)
        #expect(isDirectory.boolValue)
    }
}
