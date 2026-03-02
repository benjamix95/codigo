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

    static func toolRuntimeReadOnlyPolicy(from config: ProviderFactoryConfig) -> ToolRuntimePolicy {
        let base = toolRuntimePolicy(from: config)
        return ToolRuntimePolicy(
            sandboxMode: "workspace-read",
            askForApproval: base.askForApproval,
            timeoutMs: base.timeoutMs,
            maxToolCallsPerRound: base.maxToolCallsPerRound,
            maxRepeatedSameToolPerRound: base.maxRepeatedSameToolPerRound,
            maxBashOutputBytes: base.maxBashOutputBytes,
            maxReadBytesPerFile: base.maxReadBytesPerFile,
            allowDangerousShellPatterns: false,
            allowMutatingTools: false,
            enableMCP: base.enableMCP,
            enforceMCPEditOnly: base.enforceMCPEditOnly,
            mcpPerCallTimeoutMs: base.mcpPerCallTimeoutMs,
            mcpSessionIdleTTLSeconds: base.mcpSessionIdleTTLSeconds
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
        toolPolicy: ToolRuntimePolicy? = nil,
        environmentOverride: [String: String]? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
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
        let effectivePolicy = toolPolicy ?? toolRuntimePolicy(from: config)
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
            policy: effectivePolicy,
            executionScope: executionScope,
            executionController: executionController,
            subagentProviderFactory: subagentProviderFactory
        )
    }

    static func claudeProvider(
        config: ProviderFactoryConfig, executionController: ExecutionController?,
        executionScope: ExecutionScope = .agent,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        environmentOverride: [String: String]? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
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
        let effectivePolicy = toolPolicy ?? toolRuntimePolicy(from: config)
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
            policy: effectivePolicy,
            executionScope: executionScope,
            executionController: executionController,
            subagentProviderFactory: subagentProviderFactory
        )
    }

    static func geminiProvider(
        config: ProviderFactoryConfig, executionController: ExecutionController?,
        executionScope: ExecutionScope = .agent,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        environmentOverride: [String: String]? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = GeminiCLIProvider(
            geminiPath: config.geminiCliPath.isEmpty ? nil : config.geminiCliPath,
            modelOverride: config.geminiModelOverride.isEmpty ? nil : config.geminiModelOverride,
            executionController: executionController,
            executionScope: executionScope,
            environmentOverride: environmentOverride
        )
        guard config.unifiedToolRuntimeEnabled else { return base }
        let effectivePolicy = toolPolicy ?? toolRuntimePolicy(from: config)
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
            policy: effectivePolicy,
            executionScope: executionScope,
            executionController: executionController,
            subagentProviderFactory: subagentProviderFactory
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

    /// All provider IDs that can serve as subagent backends (CLI + API). Used for round-robin.
    private static let allSubagentBackendIds: [String] = [
        "codex-cli", "claude-cli", "gemini-cli",
        "openai-api", "anthropic-api", "google-api",
        "openrouter-api", "minimax-api", "grok-api"
    ]

    /// Builds a thread-safe factory that returns subagent providers in round-robin order.
    /// Each subagent can use a different backend across ALL configured providers (CLI + API).
    /// Returns nil if no provider can be resolved (caller should pass nil to use main agent for subagents).
    static func subagentProviderFactory(
        config: ProviderFactoryConfig,
        executionController: ExecutionController?,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        backendIds: [String]? = nil
    ) -> (@Sendable () -> any LLMProvider)? {
        let ids = backendIds ?? allSubagentBackendIds
        var providers: [any LLMProvider] = ids.compactMap { id in
            resolveSwarmBackendProvider(
                backendId: id,
                config: config,
                executionController: executionController,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths
            )
        }
        if providers.isEmpty {
            // Fallback: try defaults
            for id in allSubagentBackendIds where !ids.contains(id) {
                if let p = resolveSwarmBackendProvider(
                    backendId: id,
                    config: config,
                    executionController: executionController,
                    codebaseIndex: codebaseIndex,
                    workspacePaths: workspacePaths
                ) {
                    providers = [p]
                    break
                }
            }
        }
        guard let first = providers.first else { return nil }
        if providers.count == 1 {
            return { first }
        }
        let providerList = providers
        final class RoundRobinState: @unchecked Sendable {
            var index = 0
        }
        let state = RoundRobinState()
        let queue = DispatchQueue(label: "subagent.factory.roundrobin")
        return { @Sendable in
            queue.sync {
                let i = state.index % providerList.count
                state.index += 1
                return providerList[i]
            }
        }
    }

    /// Resolve any backend identifier to a concrete LLMProvider.
    static func resolveSwarmBackendProvider(
        backendId: String,
        config: ProviderFactoryConfig,
        executionController: ExecutionController?,
        executionScope: ExecutionScope = .agent,
        toolPolicyOverride: ToolRuntimePolicy? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = []
    ) -> (any LLMProvider)? {
        switch backendId {
        case "codex", "codex-cli":
            return codexProvider(
                config: config,
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                toolPolicy: toolPolicyOverride
            )
        case "claude", "claude-cli":
            return claudeProvider(
                config: config,
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                toolPolicy: toolPolicyOverride
            )
        case "gemini", "gemini-cli":
            return geminiProvider(
                config: config,
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                toolPolicy: toolPolicyOverride
            )
        case "openai":
            guard !config.openaiApiKey.isEmpty else { return nil }
            return openAIAPIProvider(
                config: config,
                executionScope: executionScope,
                executionController: executionController,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                toolPolicy: toolPolicyOverride
            )
        case "openai-api":
            guard !config.openaiApiKey.isEmpty else { return nil }
            return openAIAPIProvider(
                config: config,
                executionScope: executionScope,
                executionController: executionController,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                toolPolicy: toolPolicyOverride
            )
        case "anthropic-api":
            guard !config.anthropicApiKey.isEmpty else { return nil }
            return anthropicAPIProvider(
                config: config,
                executionScope: executionScope,
                executionController: executionController,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                toolPolicy: toolPolicyOverride
            )
        case "google-api":
            guard !config.googleApiKey.isEmpty else { return nil }
            return googleAPIProvider(
                config: config,
                executionScope: executionScope,
                executionController: executionController,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                toolPolicy: toolPolicyOverride
            )
        case "openrouter-api", "openrouter":
            guard !config.openrouterApiKey.isEmpty else { return nil }
            return openRouterAPIProvider(
                config: config,
                executionScope: executionScope,
                executionController: executionController,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                toolPolicy: toolPolicyOverride
            )
        case "minimax-api":
            guard !config.minimaxApiKey.isEmpty else { return nil }
            return miniMaxAPIProvider(
                config: config,
                executionScope: executionScope,
                executionController: executionController,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                toolPolicy: toolPolicyOverride
            )
        case "grok-api":
            guard !config.grokApiKey.isEmpty else { return nil }
            return grokAPIProvider(
                config: config,
                executionScope: executionScope,
                executionController: executionController,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                toolPolicy: toolPolicyOverride
            )
        default:
            return nil
        }
    }

    /// Returns the base LLM provider (without ToolEnabledLLMProvider wrapper) for lightweight tasks
    /// (e.g. prompt optimization) that don't need tools, policy, or heavy system prompts.
    /// Returns nil if the provider is not configured or not suitable for lightweight use.
    static func lightweightProvider(
        providerId: String,
        config: ProviderFactoryConfig,
        executionController: ExecutionController? = nil
    ) -> (any LLMProvider)? {
        switch normalizedBackendId(providerId) {
        case "codex", "codex-cli":
            return CodexCLIProvider(
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
                executionScope: .agent,
                environmentOverride: codexEnvironmentOverride(nil)
            )
        case "claude", "claude-cli":
            return ClaudeCLIProvider(
                claudePath: config.claudePath.isEmpty ? nil : config.claudePath,
                model: config.claudeModel,
                allowedTools: [],  // No tools for lightweight
                executionController: executionController,
                executionScope: .agent,
                environmentOverride: nil
            )
        case "gemini", "gemini-cli":
            return GeminiCLIProvider(
                geminiPath: config.geminiCliPath.isEmpty ? nil : config.geminiCliPath,
                modelOverride: config.geminiModelOverride.isEmpty ? nil : config.geminiModelOverride,
                executionController: executionController,
                executionScope: .agent,
                environmentOverride: nil
            )
        case "openai-api", "openai":
            guard !config.openaiApiKey.isEmpty else { return nil }
            return OpenAIAPIProvider(
                apiKey: config.openaiApiKey,
                model: config.openaiModel,
                reasoningEffort: nil
            )
        case "anthropic-api":
            guard !config.anthropicApiKey.isEmpty else { return nil }
            return AnthropicAPIProvider(
                apiKey: config.anthropicApiKey,
                model: config.anthropicModel,
                displayName: "Anthropic"
            )
        case "google-api":
            guard !config.googleApiKey.isEmpty else { return nil }
            return OpenAIAPIProvider(
                apiKey: config.googleApiKey,
                model: config.googleModel,
                id: "google-api",
                displayName: "Google Gemini",
                baseURL: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
            )
        case "openrouter-api", "openrouter":
            guard !config.openrouterApiKey.isEmpty else { return nil }
            return OpenAIAPIProvider(
                apiKey: config.openrouterApiKey,
                model: normalizeOpenRouterModelId(config.openrouterModel),
                id: "openrouter-api",
                displayName: "OpenRouter",
                baseURL: "https://openrouter.ai/api/v1/chat/completions",
                extraHeaders: ["HTTP-Referer": "https://codigo.app", "X-Title": "Codigo"]
            )
        case "minimax-api":
            guard !config.minimaxApiKey.isEmpty else { return nil }
            return OpenAIAPIProvider(
                apiKey: config.minimaxApiKey,
                model: config.minimaxModel,
                id: "minimax-api",
                displayName: "MiniMax",
                baseURL: "https://api.minimax.io/v1/chat/completions"
            )
        case "grok-api":
            guard !config.grokApiKey.isEmpty else { return nil }
            return OpenAIAPIProvider(
                apiKey: config.grokApiKey,
                model: config.grokModel,
                id: "grok-api",
                displayName: "Grok (xAI)",
                baseURL: "https://api.x.ai/v1/chat/completions"
            )
        default:
            return nil
        }
    }

    /// Build a UnifiedToolRuntime with optional codebase index
    private static func buildRuntime(
        executionController: ExecutionController?,
        executionScope: ExecutionScope,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        webSearchProvider: String? = nil,
        webSearchApiKeys: [String: String]? = nil,
        terminalBridge: (any TerminalBridge)? = nil,
        browserBridge: (any BrowserBridge)? = nil
    ) -> UnifiedToolRuntime {
        UnifiedToolRuntime(
            executionController: executionController,
            executionScope: executionScope,
            index: codebaseIndex,
            workspacePaths: workspacePaths,
            webSearchProvider: webSearchProvider,
            webSearchApiKeys: webSearchApiKeys,
            terminalBridge: terminalBridge,
            browserBridge: browserBridge
        )
    }

    static func openAIAPIProvider(
        config: ProviderFactoryConfig, reasoningEffort: String? = nil,
        executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = OpenAIAPIProvider(
            apiKey: config.openaiApiKey,
            model: config.openaiModel,
            reasoningEffort: reasoningEffort
        )
        let effectivePolicy = toolPolicy ?? toolRuntimePolicy(from: config)
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
            policy: effectivePolicy,
            executionScope: executionScope,
            executionController: executionController,
            subagentProviderFactory: subagentProviderFactory
        )
    }

    static func anthropicAPIProvider(
        config: ProviderFactoryConfig, executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = AnthropicAPIProvider(
            apiKey: config.anthropicApiKey,
            model: config.anthropicModel,
            displayName: "Anthropic"
        )
        let effectivePolicy = toolPolicy ?? toolRuntimePolicy(from: config)
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
            policy: effectivePolicy,
            executionScope: executionScope,
            executionController: executionController,
            subagentProviderFactory: subagentProviderFactory
        )
    }

    static func googleAPIProvider(
        config: ProviderFactoryConfig, executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = OpenAIAPIProvider(
            apiKey: config.googleApiKey,
            model: config.googleModel,
            id: "google-api",
            displayName: "Google Gemini",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        )
        let effectivePolicy = toolPolicy ?? toolRuntimePolicy(from: config)
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
            policy: effectivePolicy,
            executionScope: executionScope,
            executionController: executionController,
            subagentProviderFactory: subagentProviderFactory
        )
    }

    static func miniMaxAPIProvider(
        config: ProviderFactoryConfig,
        executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = OpenAIAPIProvider(
            apiKey: config.minimaxApiKey,
            model: config.minimaxModel,
            id: "minimax-api",
            displayName: "MiniMax",
            baseURL: "https://api.minimax.io/v1/chat/completions"
        )
        let effectivePolicy = toolPolicy ?? toolRuntimePolicy(from: config)
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
            policy: effectivePolicy,
            executionScope: executionScope,
            executionController: executionController,
            subagentProviderFactory: subagentProviderFactory
        )
    }

    static func openRouterAPIProvider(
        config: ProviderFactoryConfig, executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = OpenAIAPIProvider(
            apiKey: config.openrouterApiKey,
            model: normalizeOpenRouterModelId(config.openrouterModel),
            id: "openrouter-api",
            displayName: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1/chat/completions",
            extraHeaders: ["HTTP-Referer": "https://codigo.app", "X-Title": "Codigo"]
        )
        let effectivePolicy = toolPolicy ?? toolRuntimePolicy(from: config)
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
            policy: effectivePolicy,
            executionScope: executionScope,
            executionController: executionController,
            subagentProviderFactory: subagentProviderFactory
        )
    }

    static func grokAPIProvider(
        config: ProviderFactoryConfig, executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = OpenAIAPIProvider(
            apiKey: config.grokApiKey,
            model: config.grokModel,
            id: "grok-api",
            displayName: "Grok (xAI)",
            baseURL: "https://api.x.ai/v1/chat/completions"
        )
        let effectivePolicy = toolPolicy ?? toolRuntimePolicy(from: config)
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
            policy: effectivePolicy,
            executionScope: executionScope,
            executionController: executionController,
            subagentProviderFactory: subagentProviderFactory
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
            executionScope: .review,
            toolPolicyOverride: toolRuntimeReadOnlyPolicy(from: config),
            codebaseIndex: codebaseIndex,
            workspacePaths: workspacePaths
        ) else { return nil }

        guard let executionProvider = resolveSwarmBackendProvider(
            backendId: resolvedExecutionId,
            config: config,
            executionController: executionController,
            executionScope: .review,
            codebaseIndex: codebaseIndex,
            workspacePaths: workspacePaths
        ) else { return nil }

        let reviewConfig = MultiSwarmReviewConfig(
            maxWorkers: config.codeReviewPartitions,
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
