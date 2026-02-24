import CoderEngine
import Foundation

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
    var grokApiKey: String
    var grokModel: String

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
    var codeReviewExecutionBackend: String

    var claudePath: String
    var claudeModel: String
    var claudeAllowedTools: [String]
    var geminiCliPath: String
    var geminiModelOverride: String
}

enum ProviderFactory {
    private static func codexEnvironmentOverride(
        _ environmentOverride: [String: String]?
    ) -> [String: String]? {
        var merged = environmentOverride ?? [:]
        let current = merged["RUST_LOG"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if current.isEmpty {
            merged["RUST_LOG"] = "error"
        }
        return merged.isEmpty ? nil : merged
    }

    static func sandbox(from config: ProviderFactoryConfig) -> CodexSandboxMode {
        if config.codexSessionFullAccess { return .dangerFullAccess }
        return CodexSandboxMode(rawValue: config.codexSandbox).map { $0 } ?? .workspaceWrite
    }

    static func askForApproval(from config: ProviderFactoryConfig) -> String {
        config.globalYolo
            ? "never" : CodexCLIProvider.normalizeAskForApproval(config.codexAskForApproval)
    }

    static func toolRuntimePolicy(from config: ProviderFactoryConfig) -> ToolRuntimePolicy {
        ToolRuntimePolicy(
            sandboxMode: sandbox(from: config).rawValue,
            askForApproval: askForApproval(from: config)
        )
    }

    static func codexProvider(
        config: ProviderFactoryConfig, executionController: ExecutionController?,
        environmentOverride: [String: String]? = nil
    ) -> CodexCLIProvider {
        CodexCLIProvider(
            codexPath: config.codexPath.isEmpty ? nil : config.codexPath,
            sandboxMode: sandbox(from: config),
            modelOverride: config.codexModelOverride.isEmpty ? nil : config.codexModelOverride,
            modelReasoningEffort: config.codexReasoningEffort.isEmpty
                ? nil : config.codexReasoningEffort,
            yoloMode: config.globalYolo,
            askForApproval: askForApproval(from: config),
            executionController: executionController,
            environmentOverride: codexEnvironmentOverride(environmentOverride)
        )
    }

    static func claudeProvider(
        config: ProviderFactoryConfig, executionController: ExecutionController?,
        environmentOverride: [String: String]? = nil
    ) -> ClaudeCLIProvider {
        ClaudeCLIProvider(
            claudePath: config.claudePath.isEmpty ? nil : config.claudePath,
            model: config.claudeModel,
            allowedTools: config.claudeAllowedTools,
            executionController: executionController,
            environmentOverride: environmentOverride
        )
    }

    static func geminiProvider(
        config: ProviderFactoryConfig, executionController: ExecutionController?,
        environmentOverride: [String: String]? = nil
    ) -> GeminiCLIProvider {
        GeminiCLIProvider(
            geminiPath: config.geminiCliPath.isEmpty ? nil : config.geminiCliPath,
            modelOverride: config.geminiModelOverride.isEmpty ? nil : config.geminiModelOverride,
            executionController: executionController,
            environmentOverride: environmentOverride
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

    /// Resolve any backend identifier to a concrete LLMProvider.
    static func resolveSwarmBackendProvider(
        backendId: String,
        config: ProviderFactoryConfig,
        executionController: ExecutionController?,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = []
    ) -> (any LLMProvider)? {
        switch backendId {
        case "codex":
            return codexProvider(config: config, executionController: executionController)
        case "claude":
            return claudeProvider(config: config, executionController: executionController)
        case "gemini":
            return geminiProvider(config: config, executionController: executionController)
        case "openai":
            guard !config.openaiApiKey.isEmpty else { return nil }
            return openAIAPIProvider(config: config, executionController: executionController, codebaseIndex: codebaseIndex, workspacePaths: workspacePaths)
        case "openai-api":
            guard !config.openaiApiKey.isEmpty else { return nil }
            return openAIAPIProvider(config: config, executionController: executionController, codebaseIndex: codebaseIndex, workspacePaths: workspacePaths)
        case "anthropic-api":
            guard !config.anthropicApiKey.isEmpty else { return nil }
            return anthropicAPIProvider(config: config, executionController: executionController, codebaseIndex: codebaseIndex, workspacePaths: workspacePaths)
        case "google-api":
            guard !config.googleApiKey.isEmpty else { return nil }
            return googleAPIProvider(config: config, executionController: executionController, codebaseIndex: codebaseIndex, workspacePaths: workspacePaths)
        case "openrouter-api", "openrouter":
            guard !config.openrouterApiKey.isEmpty else { return nil }
            return openRouterAPIProvider(config: config, executionController: executionController, codebaseIndex: codebaseIndex, workspacePaths: workspacePaths)
        case "minimax-api":
            guard !config.minimaxApiKey.isEmpty else { return nil }
            return miniMaxAPIProvider(config: config, executionController: executionController, codebaseIndex: codebaseIndex, workspacePaths: workspacePaths)
        case "grok-api":
            guard !config.grokApiKey.isEmpty else { return nil }
            return grokAPIProvider(config: config, executionController: executionController, codebaseIndex: codebaseIndex, workspacePaths: workspacePaths)
        default:
            return nil
        }
    }

    static func swarmProvider(
        config: ProviderFactoryConfig, executionController: ExecutionController?
    ) -> SwarmRuntimeProvider? {
        let orchBackend = OrchestratorBackend(rawValue: config.swarmOrchestrator) ?? .openai
        let workerBackend = WorkerBackend(rawValue: config.swarmWorkerBackend) ?? .codex

        guard
            let orchProvider = resolveSwarmBackendProvider(
                backendId: config.swarmOrchestrator,
                config: config,
                executionController: executionController
            )
        else { return nil }

        guard
            let workerProvider = resolveSwarmBackendProvider(
                backendId: config.swarmWorkerBackend,
                config: config,
                executionController: executionController
            )
        else { return nil }

        let enabledRoles = parseRoles(config.swarmEnabledRoles)

        let swarmConfig = SwarmConfig(
            orchestratorBackend: orchBackend,
            workerBackend: workerBackend,
            enabledRoles: enabledRoles.isEmpty ? nil : enabledRoles,
            autoPostCodePipeline: config.swarmAutoPostCodePipeline,
            maxPostCodeRetries: config.swarmMaxPostCodeRetries,
            maxReviewLoops: config.swarmMaxReviewLoops
        )
        return SwarmRuntimeProvider(
            config: swarmConfig,
            orchestratorProvider: orchProvider,
            workerProvider: workerProvider,
            executionController: executionController
        )
    }

    private static func codeReviewExecutionProvider(
        config: ProviderFactoryConfig, codex: CodexCLIProvider, claude: ClaudeCLIProvider?
    ) -> (any LLMProvider)? {
        switch config.codeReviewExecutionBackend {
        case "codex", "codex-cli":
            return CodexCLIProvider(
                codexPath: config.codexPath.isEmpty ? nil : config.codexPath,
                sandboxMode: sandbox(from: config),
                modelOverride: config.codexModelOverride.isEmpty ? nil : config.codexModelOverride,
                modelReasoningEffort: config.codexReasoningEffort.isEmpty
                    ? nil : config.codexReasoningEffort,
                yoloMode: config.globalYolo,
                askForApproval: askForApproval(from: config),
                executionController: nil,
                executionScope: .review,
                environmentOverride: codexEnvironmentOverride(nil)
            )
        case "claude", "claude-cli":
            guard let c = claude, c.isAuthenticated() else { return nil }
            return ClaudeCLIProvider(
                claudePath: config.claudePath.isEmpty ? nil : config.claudePath,
                model: config.claudeModel,
                allowedTools: config.claudeAllowedTools,
                executionController: nil,
                executionScope: .review
            )
        case "gemini", "gemini-cli":
            return GeminiCLIProvider(
                geminiPath: config.geminiCliPath.isEmpty ? nil : config.geminiCliPath,
                modelOverride: config.geminiModelOverride.isEmpty ? nil : config.geminiModelOverride,
                executionController: nil,
                executionScope: .review
            )
        case "anthropic-api":
            guard !config.anthropicApiKey.isEmpty else { return nil }
            return anthropicAPIProvider(config: config, executionScope: .review)
        case "openai-api":
            guard !config.openaiApiKey.isEmpty else { return nil }
            return openAIAPIProvider(config: config, executionScope: .review)
        case "google-api":
            guard !config.googleApiKey.isEmpty else { return nil }
            return googleAPIProvider(config: config, executionScope: .review)
        case "openrouter-api":
            guard !config.openrouterApiKey.isEmpty else { return nil }
            return openRouterAPIProvider(config: config, executionScope: .review)
        case "minimax-api":
            guard !config.minimaxApiKey.isEmpty else { return nil }
            return miniMaxAPIProvider(config: config, executionScope: .review, executionController: nil)
        case "grok-api":
            guard !config.grokApiKey.isEmpty else { return nil }
            return grokAPIProvider(config: config, executionScope: .review, executionController: nil)
        default:
            return codex
        }
    }

    /// Build a UnifiedToolRuntime with optional codebase index
    private static func buildRuntime(
        executionController: ExecutionController?,
        executionScope: ExecutionScope,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = []
    ) -> UnifiedToolRuntime {
        UnifiedToolRuntime(
            executionController: executionController,
            executionScope: executionScope,
            index: codebaseIndex,
            workspacePaths: workspacePaths
        )
    }

    static func openAIAPIProvider(
        config: ProviderFactoryConfig, reasoningEffort: String? = nil,
        executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = []
    ) -> any LLMProvider {
        let base = OpenAIAPIProvider(
            apiKey: config.openaiApiKey,
            model: config.openaiModel,
            reasoningEffort: reasoningEffort
        )
        return ToolEnabledLLMProvider(
            base: base,
            runtime: buildRuntime(
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths
            ),
            policy: toolRuntimePolicy(from: config),
            executionScope: executionScope,
            executionController: executionController
        )
    }

    static func anthropicAPIProvider(
        config: ProviderFactoryConfig, executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = []
    ) -> any LLMProvider {
        let base = AnthropicAPIProvider(
            apiKey: config.anthropicApiKey,
            model: config.anthropicModel,
            displayName: "Anthropic"
        )
        return ToolEnabledLLMProvider(
            base: base,
            runtime: buildRuntime(
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths
            ),
            policy: toolRuntimePolicy(from: config),
            executionScope: executionScope,
            executionController: executionController
        )
    }

    static func googleAPIProvider(
        config: ProviderFactoryConfig, executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = []
    ) -> any LLMProvider {
        let base = OpenAIAPIProvider(
            apiKey: config.googleApiKey,
            model: config.googleModel,
            id: "google-api",
            displayName: "Google Gemini",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        )
        return ToolEnabledLLMProvider(
            base: base,
            runtime: buildRuntime(
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths
            ),
            policy: toolRuntimePolicy(from: config),
            executionScope: executionScope,
            executionController: executionController
        )
    }

    static func miniMaxAPIProvider(
        config: ProviderFactoryConfig,
        executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = []
    ) -> any LLMProvider {
        let base = OpenAIAPIProvider(
            apiKey: config.minimaxApiKey,
            model: config.minimaxModel,
            id: "minimax-api",
            displayName: "MiniMax",
            baseURL: "https://api.minimax.io/v1/chat/completions"
        )
        return ToolEnabledLLMProvider(
            base: base,
            runtime: buildRuntime(
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths
            ),
            policy: toolRuntimePolicy(from: config),
            executionScope: executionScope,
            executionController: executionController
        )
    }

    static func openRouterAPIProvider(
        config: ProviderFactoryConfig, executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = []
    ) -> any LLMProvider {
        let base = OpenAIAPIProvider(
            apiKey: config.openrouterApiKey,
            model: normalizeOpenRouterModelId(config.openrouterModel),
            id: "openrouter-api",
            displayName: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1/chat/completions",
            extraHeaders: ["HTTP-Referer": "https://codigo.app", "X-Title": "Codigo"]
        )
        return ToolEnabledLLMProvider(
            base: base,
            runtime: buildRuntime(
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths
            ),
            policy: toolRuntimePolicy(from: config),
            executionScope: executionScope,
            executionController: executionController
        )
    }

    static func grokAPIProvider(
        config: ProviderFactoryConfig, executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = []
    ) -> any LLMProvider {
        let base = OpenAIAPIProvider(
            apiKey: config.grokApiKey,
            model: config.grokModel,
            id: "grok-api",
            displayName: "Grok (xAI)",
            baseURL: "https://api.x.ai/v1/chat/completions"
        )
        return ToolEnabledLLMProvider(
            base: base,
            runtime: buildRuntime(
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths
            ),
            policy: toolRuntimePolicy(from: config),
            executionScope: executionScope,
            executionController: executionController
        )
    }
}
