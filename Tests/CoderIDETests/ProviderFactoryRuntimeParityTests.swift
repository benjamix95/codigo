import XCTest
import CoderEngine
@testable import CoderIDE

final class ProviderFactoryRuntimeParityTests: XCTestCase {
    func testAPIProvidersReceiveCodebaseIndexAndWorkspacePaths() async throws {
        let config = makeConfig()
        let index = CodebaseIndex()
        let workspacePaths = makeWorkspacePaths()

        let providers: [(expectedId: String, provider: any LLMProvider)] = [
            (
                "openai-api",
                ProviderFactory.openAIAPIProvider(
                    config: config,
                    executionController: nil,
                    codebaseIndex: index,
                    workspacePaths: workspacePaths
                )
            ),
            (
                "anthropic-api",
                ProviderFactory.anthropicAPIProvider(
                    config: config,
                    executionController: nil,
                    codebaseIndex: index,
                    workspacePaths: workspacePaths
                )
            ),
            (
                "google-api",
                ProviderFactory.googleAPIProvider(
                    config: config,
                    executionController: nil,
                    codebaseIndex: index,
                    workspacePaths: workspacePaths
                )
            ),
            (
                "openrouter-api",
                ProviderFactory.openRouterAPIProvider(
                    config: config,
                    executionController: nil,
                    codebaseIndex: index,
                    workspacePaths: workspacePaths
                )
            ),
            (
                "minimax-api",
                ProviderFactory.miniMaxAPIProvider(
                    config: config,
                    executionController: nil,
                    codebaseIndex: index,
                    workspacePaths: workspacePaths
                )
            ),
            (
                "grok-api",
                ProviderFactory.grokAPIProvider(
                    config: config,
                    executionController: nil,
                    codebaseIndex: index,
                    workspacePaths: workspacePaths
                )
            ),
        ]

        let expectedWorkspacePaths = workspacePaths.map(\.path)
        for entry in providers {
            XCTAssertEqual(entry.provider.id, entry.expectedId)
            guard let toolProvider = entry.provider as? ToolEnabledLLMProvider else {
                XCTFail("Expected ToolEnabledLLMProvider for \(entry.expectedId)")
                continue
            }
            let snapshot = await toolProvider.debugToolRuntimeSnapshot()
            XCTAssertTrue(snapshot.hasCodebaseIndex, "Missing index in \(entry.expectedId)")
            XCTAssertEqual(snapshot.workspacePaths, expectedWorkspacePaths)
            XCTAssertEqual(snapshot.executionScope, .agent)
        }
    }

    func testSwarmProviderPassesRuntimeParityToOrchestratorAndWorker() async throws {
        let config = makeConfig()
        let index = CodebaseIndex()
        let workspacePaths = makeWorkspacePaths()

        guard let swarm = ProviderFactory.swarmProvider(
            config: config,
            executionController: nil,
            agentProviderId: nil,
            codebaseIndex: index,
            workspacePaths: workspacePaths
        ) else {
            return XCTFail("Expected swarm provider")
        }

        let snapshot = await swarm.debugSwarmSnapshot()
        XCTAssertEqual(snapshot.orchestratorProviderId, "openai-api")
        XCTAssertEqual(snapshot.workerProviderId, "anthropic-api")

        let expectedWorkspacePaths = workspacePaths.map(\.path)
        guard let orchestratorRuntime = snapshot.orchestratorRuntime else {
            return XCTFail("Expected orchestrator runtime snapshot")
        }
        guard let workerRuntime = snapshot.workerRuntime else {
            return XCTFail("Expected worker runtime snapshot")
        }
        XCTAssertTrue(orchestratorRuntime.hasCodebaseIndex)
        XCTAssertTrue(workerRuntime.hasCodebaseIndex)
        XCTAssertEqual(orchestratorRuntime.workspacePaths, expectedWorkspacePaths)
        XCTAssertEqual(workerRuntime.workspacePaths, expectedWorkspacePaths)
    }

    private func makeWorkspacePaths() -> [URL] {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            "provider-runtime-parity-\(UUID().uuidString)"
        )
        let first = root.appendingPathComponent("workspace-a")
        let second = root.appendingPathComponent("workspace-b")
        return [first, second]
    }

    private func makeConfig() -> ProviderFactoryConfig {
        ProviderFactoryConfig(
            openaiApiKey: "openai-test-key",
            openaiModel: "gpt-4o-mini",
            anthropicApiKey: "anthropic-test-key",
            anthropicModel: "claude-3-5-haiku-latest",
            googleApiKey: "google-test-key",
            googleModel: "gemini-2.0-flash",
            minimaxApiKey: "minimax-test-key",
            minimaxModel: "MiniMax-M1",
            openrouterApiKey: "openrouter-test-key",
            openrouterModel: "openai/gpt-4o-mini",
            grokApiKey: "grok-test-key",
            grokModel: "grok-3-mini",
            codexPath: "",
            codexSandbox: "workspace-write",
            codexSessionFullAccess: false,
            codexAskForApproval: "never",
            codexModelOverride: "",
            codexReasoningEffort: "",
            planModeBackend: "openai-api",
            swarmOrchestrator: "openai-api",
            swarmWorkerBackend: "anthropic-api",
            swarmAutoPostCodePipeline: false,
            swarmMaxPostCodeRetries: 1,
            swarmMaxReviewLoops: 1,
            swarmEnabledRoles: "",
            globalYolo: false,
            codeReviewPartitions: 2,
            codeReviewAnalysisOnly: false,
            codeReviewMaxRounds: 2,
            codeReviewAnalysisBackend: "google-api",
            codeReviewExecutionBackend: "openrouter-api",
            claudePath: "",
            claudeModel: "claude-3-5-sonnet-latest",
            claudeAllowedTools: [],
            geminiCliPath: "",
            geminiModelOverride: "",
            webSearchProvider: "duckduckgo",
            braveSearchApiKey: "",
            tavilyApiKey: "",
            serperApiKey: ""
        )
    }
}
