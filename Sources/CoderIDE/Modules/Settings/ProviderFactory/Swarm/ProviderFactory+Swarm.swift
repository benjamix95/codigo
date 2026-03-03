import CoderEngine
import Foundation

extension ProviderFactory {
    private static let allSubagentBackendIds: [String] = [
        "codex-cli", "claude-cli", "gemini-cli",
        "openai-api", "anthropic-api", "google-api",
        "openrouter-api", "minimax-api", "grok-api"
    ]

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

    /// Builds a thread-safe factory that returns subagent providers in round-robin order.
    /// Each subagent can use a different backend across ALL configured providers (CLI + API).
    /// Returns nil if no provider is configured.
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
