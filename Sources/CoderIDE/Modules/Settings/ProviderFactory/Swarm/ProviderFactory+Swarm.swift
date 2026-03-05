import CoderEngine
import Foundation

extension ProviderFactory {
    static let allSubagentBackendIds: [String] = [
        "codex-cli", "claude-cli", "gemini-cli",
        "openai-api", "anthropic-api", "google-api",
        "openrouter-api", "minimax-api", "grok-api"
    ]

    /// Maps a selected real provider id to the corresponding swarm backend id.
    static func swarmBackendIdForAgentProvider(_ providerId: String?) -> String? {
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

    static func resolveSwarmBackendId(
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

    /// Builds a subagent factory aligned with the unified swarm/backend routing.
    /// When `backendIds` is omitted, the factory resolves the preferred worker backend
    /// from settings and, for `auto`, inherits from the parent provider identity.
    /// The returned factory is deterministic: it keeps using the same resolved backend
    /// instead of round-robin cycling through unrelated providers.
    static func subagentProviderFactory(
        config: ProviderFactoryConfig,
        executionController: ExecutionController?,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        agentProviderId: String? = nil,
        backendIds: [String]? = nil
    ) -> (@Sendable () -> any LLMProvider)? {
        let orderedBackendIds = preferredSubagentBackendIds(
            config: config,
            agentProviderId: agentProviderId,
            backendIds: backendIds
        )
        let providers: [any LLMProvider] = orderedBackendIds.compactMap { backendId in
            resolveSwarmBackendProvider(
                backendId: backendId,
                config: config,
                executionController: executionController,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths
            )
        }
        guard let first = providers.first else { return nil }
        return { first }
    }

    static func subagentProviderFactoryForParent(
        _ providerId: String,
        config: ProviderFactoryConfig,
        executionController: ExecutionController?,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = []
    ) -> (@Sendable () -> any LLMProvider)? {
        subagentProviderFactory(
            config: config,
            executionController: executionController,
            codebaseIndex: codebaseIndex,
            workspacePaths: workspacePaths,
            agentProviderId: providerId
        )
    }

    static func preferredSubagentBackendIds(
        config: ProviderFactoryConfig,
        agentProviderId: String?,
        backendIds: [String]? = nil
    ) -> [String] {
        let normalizedCandidates = (backendIds ?? [])
            .map(normalizedBackendId)
            .filter { !$0.isEmpty }

        if !normalizedCandidates.isEmpty {
            return deduplicatedBackendIds(normalizedCandidates)
        }

        let preferredBackend = resolveSwarmBackendId(
            configuredBackendId: config.swarmWorkerBackend,
            agentProviderId: agentProviderId
        )
        let fallbackBackends = allSubagentBackendIds
            .map(normalizedBackendId)
            .filter { $0 != preferredBackend }
        return deduplicatedBackendIds([preferredBackend] + fallbackBackends)
    }

    private static func deduplicatedBackendIds(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for id in ids where seen.insert(id).inserted {
            ordered.append(id)
        }
        return ordered
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
        switch normalizedBackendId(backendId) {
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
        case "openai", "openai-api":
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
        case "openrouter", "openrouter-api":
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
}
