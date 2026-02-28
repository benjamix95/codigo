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
    var codexModelProvider: String
    var codexPreferResponsesWireAPI: Bool
    var planModeBackend: String

    var swarmOrchestrator: String
    var swarmWorkerBackend: String
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
    var unifiedToolRuntimeEnabled: Bool
    var agentsHardBlockEnabled: Bool
    var mcpEditEnforcementEnabled: Bool

    var webSearchProvider: String
    var braveSearchApiKey: String
    var tavilyApiKey: String
    var serperApiKey: String

    /// Build a `[String: String]` keys map suitable for `UnifiedToolRuntime`.
    var webSearchApiKeys: [String: String] {
        var keys: [String: String] = [:]
        if !braveSearchApiKey.isEmpty { keys["brave"] = braveSearchApiKey }
        if !tavilyApiKey.isEmpty { keys["tavily"] = tavilyApiKey }
        if !serperApiKey.isEmpty { keys["serper"] = serperApiKey }
        return keys
    }
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
            askForApproval: askForApproval(from: config),
            enforceMCPEditOnly: config.mcpEditEnforcementEnabled
        )
    }

    static func normalizedToolList(from raw: String) -> [String] {
        var seen = Set<String>()
        var tools: [String] = []
        for token in raw.components(separatedBy: ",") {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                tools.append(trimmed)
            }
        }
        return tools
    }

    static func codexProvider(
        config: ProviderFactoryConfig, executionController: ExecutionController?,
        executionScope: ExecutionScope = .agent,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        environmentOverride: [String: String]? = nil
    ) -> any LLMProvider {
        let base = CodexCLIProvider(
            codexPath: config.codexPath.isEmpty ? nil : config.codexPath,
            sandboxMode: sandbox(from: config),
            modelOverride: config.codexModelOverride.isEmpty ? nil : config.codexModelOverride,
            modelReasoningEffort: config.codexReasoningEffort.isEmpty
                ? nil : config.codexReasoningEffort,
            modelProviderOverride: config.codexModelProvider.isEmpty ? nil : config.codexModelProvider,
            preferOpenAIResponsesWireAPI: config.codexPreferResponsesWireAPI,
            yoloMode: config.globalYolo,
            askForApproval: askForApproval(from: config),
            executionController: executionController,
            executionScope: executionScope,
            environmentOverride: codexEnvironmentOverride(environmentOverride)
        )
        guard config.unifiedToolRuntimeEnabled else { return base }
        return ToolEnabledLLMProvider(
            base: base,
            runtime: buildRuntime(
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                webSearchProvider: config.webSearchProvider,
                webSearchApiKeys: config.webSearchApiKeys
            ),
            policy: toolRuntimePolicy(from: config),
            executionScope: executionScope,
            executionController: executionController
        )
    }

    static func claudeProvider(
        config: ProviderFactoryConfig, executionController: ExecutionController?,
        executionScope: ExecutionScope = .agent,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        environmentOverride: [String: String]? = nil
    ) -> any LLMProvider {
        let base = ClaudeCLIProvider(
            claudePath: config.claudePath.isEmpty ? nil : config.claudePath,
            model: config.claudeModel,
            allowedTools: config.claudeAllowedTools,
            executionController: executionController,
            executionScope: executionScope,
            environmentOverride: environmentOverride
        )
        guard config.unifiedToolRuntimeEnabled else { return base }
        return ToolEnabledLLMProvider(
            base: base,
            runtime: buildRuntime(
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                webSearchProvider: config.webSearchProvider,
                webSearchApiKeys: config.webSearchApiKeys
            ),
            policy: toolRuntimePolicy(from: config),
            executionScope: executionScope,
            executionController: executionController
        )
    }

    static func geminiProvider(
        config: ProviderFactoryConfig, executionController: ExecutionController?,
        executionScope: ExecutionScope = .agent,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        environmentOverride: [String: String]? = nil
    ) -> any LLMProvider {
        let base = GeminiCLIProvider(
            geminiPath: config.geminiCliPath.isEmpty ? nil : config.geminiCliPath,
            modelOverride: config.geminiModelOverride.isEmpty ? nil : config.geminiModelOverride,
            executionController: executionController,
            executionScope: executionScope,
            environmentOverride: environmentOverride
        )
        guard config.unifiedToolRuntimeEnabled else { return base }
        return ToolEnabledLLMProvider(
            base: base,
            runtime: buildRuntime(
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                webSearchProvider: config.webSearchProvider,
                webSearchApiKeys: config.webSearchApiKeys
            ),
            policy: toolRuntimePolicy(from: config),
            executionScope: executionScope,
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

    private static func normalizedBackendId(_ backendId: String) -> String {
        backendId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Maps a selected real provider id to the corresponding swarm backend id.
    private static func swarmBackendIdForAgentProvider(_ providerId: String?) -> String? {
        switch normalizedBackendId(providerId ?? "") {
        case "codex-cli", "codex":
            return "codex"
        case "claude-cli", "claude":
            return "claude"
        case "gemini-cli", "gemini":
            return "gemini"
        case "openai-api", "openai":
            return "openai-api"
        case "anthropic-api":
            return "anthropic-api"
        case "google-api":
            return "google-api"
        case "openrouter-api", "openrouter":
            return "openrouter-api"
        case "minimax-api":
            return "minimax-api"
        case "grok-api":
            return "grok-api"
        default:
            return nil
        }
    }

    private static func resolveSwarmBackendId(
        configuredBackendId: String,
        agentProviderId: String?
    ) -> String {
        let normalized = normalizedBackendId(configuredBackendId)
        if normalized.isEmpty || normalized == "auto" {
            if let inherited = swarmBackendIdForAgentProvider(agentProviderId) {
                return inherited
            }
            return "codex"
        }
        return normalized
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
        case "codex", "codex-cli":
            return codexProvider(
                config: config,
                executionController: executionController,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths
            )
        case "claude", "claude-cli":
            return claudeProvider(
                config: config,
                executionController: executionController,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths
            )
        case "gemini", "gemini-cli":
            return geminiProvider(
                config: config,
                executionController: executionController,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths
            )
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
                modelProviderOverride: config.codexModelProvider.isEmpty
                    ? nil : config.codexModelProvider,
                preferOpenAIResponsesWireAPI: config.codexPreferResponsesWireAPI,
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
        workspacePaths: [URL] = [],
        webSearchProvider: String? = nil,
        webSearchApiKeys: [String: String]? = nil
    ) -> UnifiedToolRuntime {
        UnifiedToolRuntime(
            executionController: executionController,
            executionScope: executionScope,
            index: codebaseIndex,
            workspacePaths: workspacePaths,
            webSearchProvider: webSearchProvider,
            webSearchApiKeys: webSearchApiKeys
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
                workspacePaths: workspacePaths,
                webSearchProvider: config.webSearchProvider,
                webSearchApiKeys: config.webSearchApiKeys
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
                workspacePaths: workspacePaths,
                webSearchProvider: config.webSearchProvider,
                webSearchApiKeys: config.webSearchApiKeys
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
                workspacePaths: workspacePaths,
                webSearchProvider: config.webSearchProvider,
                webSearchApiKeys: config.webSearchApiKeys
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
                workspacePaths: workspacePaths,
                webSearchProvider: config.webSearchProvider,
                webSearchApiKeys: config.webSearchApiKeys
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
                workspacePaths: workspacePaths,
                webSearchProvider: config.webSearchProvider,
                webSearchApiKeys: config.webSearchApiKeys
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
                workspacePaths: workspacePaths,
                webSearchProvider: config.webSearchProvider,
                webSearchApiKeys: config.webSearchApiKeys
            ),
            policy: toolRuntimePolicy(from: config),
            executionScope: executionScope,
            executionController: executionController
        )
    }

    // MARK: - Code Review Multi-Swarm

    static func codeReviewMultiSwarmProvider(
        config: ProviderFactoryConfig,
        executionController: ExecutionController?,
        agentProviderId: String?,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = []
    ) -> CodeReviewMultiSwarmProvider? {
        // Resolve analysis backend (default: auto → same as agent)
        let resolvedAnalysisId = resolveSwarmBackendId(
            configuredBackendId: config.codeReviewAnalysisBackend,
            agentProviderId: agentProviderId
        )
        // Resolve execution backend (default: auto → same as agent)
        let resolvedExecutionId = resolveSwarmBackendId(
            configuredBackendId: config.codeReviewExecutionBackend,
            agentProviderId: agentProviderId
        )

        guard let analysisProvider = resolveSwarmBackendProvider(
            backendId: resolvedAnalysisId,
            config: config,
            executionController: executionController,
            codebaseIndex: codebaseIndex,
            workspacePaths: workspacePaths
        ) else { return nil }

        guard let executionProvider = resolveSwarmBackendProvider(
            backendId: resolvedExecutionId,
            config: config,
            executionController: executionController,
            codebaseIndex: codebaseIndex,
            workspacePaths: workspacePaths
        ) else { return nil }

        let reviewConfig = MultiSwarmReviewConfig(
            maxWorkers: config.codeReviewPartitions,
            yoloMode: config.globalYolo,
            enabledPhases: config.codeReviewAnalysisOnly ? .analysisOnly : .analysisAndExecution,
            maxReviewRounds: config.codeReviewMaxRounds,
            analysisBackend: resolvedAnalysisId,
            executionBackend: resolvedExecutionId
        )

        return CodeReviewMultiSwarmProvider(
            config: reviewConfig,
            analysisProvider: analysisProvider,
            executionProvider: executionProvider,
            executionController: executionController
        )
    }
}
