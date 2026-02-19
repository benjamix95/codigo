import Foundation
import CoderEngine

struct ProviderFactoryConfig {
    var openaiApiKey: String
    var openaiModel: String
    var anthropicApiKey: String
    var anthropicModel: String
    var googleApiKey: String
    var googleModel: String
    var minimaxApiKey: String
    var minimaxModel: String
    var openrouterApiKey: String
    var openrouterModel: String

    var codexPath: String
    var codexSandbox: String
    var codexSessionFullAccess: Bool
    var codexAskForApproval: String
    var codexModelOverride: String
    var codexReasoningEffort: String
    var planModeBackend: String

    var swarmOrchestrator: String
    var swarmWorkerBackend: String
    var swarmAutoPostCodePipeline: Bool
    var swarmMaxPostCodeRetries: Int
    var swarmMaxReviewLoops: Int
    var swarmEnabledRoles: String

    var globalYolo: Bool
    var codeReviewPartitions: Int
    var codeReviewAnalysisOnly: Bool
    var codeReviewMaxRounds: Int
    var codeReviewAnalysisBackend: String

    var claudePath: String
    var claudeModel: String
    var claudeAllowedTools: [String]
    var geminiCliPath: String
}

enum ProviderFactory {
    static func sandbox(from config: ProviderFactoryConfig) -> CodexSandboxMode {
        if config.codexSessionFullAccess { return .dangerFullAccess }
        return CodexSandboxMode(rawValue: config.codexSandbox).map { $0 } ?? .workspaceWrite
    }

    static func askForApproval(from config: ProviderFactoryConfig) -> String {
        config.globalYolo ? "never" : CodexCLIProvider.normalizeAskForApproval(config.codexAskForApproval)
    }

    static func codexParams(from config: ProviderFactoryConfig) -> CodexCreateParams {
        CodexCreateParams(
            codexPath: config.codexPath.isEmpty ? nil : config.codexPath,
            sandboxMode: sandbox(from: config),
            modelOverride: config.codexModelOverride.isEmpty ? nil : config.codexModelOverride,
            modelReasoningEffort: config.codexReasoningEffort.isEmpty ? nil : config.codexReasoningEffort,
            askForApproval: askForApproval(from: config)
        )
    }

    static func codexProvider(config: ProviderFactoryConfig, executionController: ExecutionController?, environmentOverride: [String: String]? = nil) -> CodexCLIProvider {
        CodexCLIProvider(
            codexPath: config.codexPath.isEmpty ? nil : config.codexPath,
            sandboxMode: sandbox(from: config),
            modelOverride: config.codexModelOverride.isEmpty ? nil : config.codexModelOverride,
            modelReasoningEffort: config.codexReasoningEffort.isEmpty ? nil : config.codexReasoningEffort,
            yoloMode: config.globalYolo,
            askForApproval: askForApproval(from: config),
            executionController: executionController,
            environmentOverride: environmentOverride
        )
    }

    static func claudeProvider(config: ProviderFactoryConfig, executionController: ExecutionController?, environmentOverride: [String: String]? = nil) -> ClaudeCLIProvider {
        ClaudeCLIProvider(
            claudePath: config.claudePath.isEmpty ? nil : config.claudePath,
            model: config.claudeModel,
            allowedTools: config.claudeAllowedTools,
            executionController: executionController,
            environmentOverride: environmentOverride
        )
    }

    static func geminiProvider(config: ProviderFactoryConfig, executionController: ExecutionController?, environmentOverride: [String: String]? = nil) -> GeminiCLIProvider {
        GeminiCLIProvider(
            geminiPath: config.geminiCliPath.isEmpty ? nil : config.geminiCliPath,
            executionController: executionController,
            environmentOverride: environmentOverride
        )
    }

    static func planProvider(config: ProviderFactoryConfig, codex: CodexCLIProvider?, claude: ClaudeCLIProvider?, executionController: ExecutionController?) -> PlanModeProvider {
        PlanModeProvider(
            codexProvider: codex,
            claudeProvider: claude,
            codexParams: codexParams(from: config),
            backend: config.planModeBackend,
            claudePath: config.claudePath.isEmpty ? nil : config.claudePath,
            claudeModel: config.claudeModel.trimmingCharacters(in: .whitespaces).isEmpty ? nil : config.claudeModel,
            executionController: executionController
        )
    }

    static func parseRoles(_ raw: String) -> Set<AgentRole> {
        var roles = Set<AgentRole>()
        for token in raw.components(separatedBy: ",") {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if let role = AgentRole(rawValue: trimmed) {
                roles.insert(role)
            }
        }
        return roles
    }

    static func swarmProvider(config: ProviderFactoryConfig, codex: CodexCLIProvider, claude: ClaudeCLIProvider?, executionController: ExecutionController?) -> AgentSwarmProvider {
        let orchBackend: OrchestratorBackend
        switch config.swarmOrchestrator {
        case "codex": orchBackend = .codex
        case "claude": orchBackend = .claude
        default: orchBackend = .openai
        }
        let workerBackend: WorkerBackend = config.swarmWorkerBackend == "claude" ? .claude : .codex
        let openAIClient: OpenAICompletionsClient? = orchBackend == .openai && !config.openaiApiKey.isEmpty
            ? OpenAICompletionsClient(apiKey: config.openaiApiKey, model: config.openaiModel)
            : nil
        let enabledRoles = parseRoles(config.swarmEnabledRoles)

        let swarmConfig = SwarmConfig(
            orchestratorBackend: orchBackend,
            workerBackend: workerBackend,
            enabledRoles: enabledRoles.isEmpty ? nil : enabledRoles,
            autoPostCodePipeline: config.swarmAutoPostCodePipeline,
            maxPostCodeRetries: config.swarmMaxPostCodeRetries,
            maxReviewLoops: config.swarmMaxReviewLoops
        )
        return AgentSwarmProvider(
            config: swarmConfig,
            openAIClient: openAIClient,
            codexProvider: codex,
            claudeProvider: claude,
            executionController: executionController
        )
    }

    static func codeReviewProvider(config: ProviderFactoryConfig, codex: CodexCLIProvider, claude: ClaudeCLIProvider?) -> MultiSwarmReviewProvider {
        let reviewConfig = MultiSwarmReviewConfig(
            partitionCount: config.codeReviewPartitions,
            yoloMode: config.globalYolo,
            enabledPhases: config.codeReviewAnalysisOnly ? .analysisOnly : .analysisAndExecution,
            maxReviewRounds: config.codeReviewMaxRounds,
            analysisBackend: config.codeReviewAnalysisBackend
        )
        return MultiSwarmReviewProvider(
            config: reviewConfig,
            codexProvider: codex,
            codexParams: codexParams(from: config),
            claudeProvider: claude
        )
    }
}
