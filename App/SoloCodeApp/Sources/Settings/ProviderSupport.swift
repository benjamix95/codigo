import CoderEngine

enum ProviderSupport {
    static let agentProviderIds = ["codex-cli", "claude-cli", "gemini-cli", "kilo-cli"]

    /// API providers that support Agent mode (tools, multi-turn, read_batch).
    static let agentApiProviderIds = [
        "openai-api",
        "anthropic-api",
        "google-api",
        "openrouter-api",
        "minimax-api",
        "grok-api"
    ]

    private static let allAgentProviderIds: [String] = agentProviderIds + agentApiProviderIds

    static func isRegisteredProvider(id: String?, registry: ProviderRegistry) -> Bool {
        guard let id else { return false }
        return registry.provider(for: id) != nil
    }

    static func isAgentProvider(id: String?) -> Bool {
        guard let id else { return false }
        return agentProviderIds.contains(id)
    }

    static func isAgentCompatibleProvider(id: String?) -> Bool {
        guard let id else { return false }
        return agentProviderIds.contains(id) || agentApiProviderIds.contains(id)
    }

    static func isUserSelectableRealProvider(id: String?) -> Bool {
        guard let id else { return false }
        return allAgentProviderIds.contains(id)
    }

    /// Returns true when provider id identifies a registered, known, and authenticated agent/API provider.
    static func isHealthyAgentProvider(id: String?, registry: ProviderRegistry) -> Bool {
        guard let id, isAgentCompatibleProvider(id: id) else { return false }
        guard let provider = registry.provider(for: id) else { return false }
        return provider.isAuthenticated()
    }

    /// Deterministic first-available provider, honoring `preferred` if healthy.
    static func firstHealthyAgentProviderId(
        preferred: String?,
        registry: ProviderRegistry
    ) -> String? {
        if isHealthyAgentProvider(id: preferred, registry: registry), let preferred {
            return preferred
        }

        for id in allAgentProviderIds where isHealthyAgentProvider(id: id, registry: registry) {
            return id
        }

        return nil
    }

    /// Strict selection policy: keep preferred/current provider identity and never
    /// auto-switch to a different provider. Authentication is checked at runtime.
    static func preferredOrCurrentAgentProviderId(
        preferred: String?,
        current: String?,
        registry: ProviderRegistry
    ) -> String? {
        if let preferred,
           isAgentCompatibleProvider(id: preferred),
           registry.provider(for: preferred) != nil {
            return preferred
        }
        if let current,
           isAgentCompatibleProvider(id: current),
           registry.provider(for: current) != nil {
            return current
        }
        return nil
    }

    /// Like `firstHealthyAgentProviderId`, but falls back to `codex-cli` when registered
    /// if no healthy provider exists. Restores legacy UX for users with unconfigured providers.
    static func firstHealthyAgentProviderIdWithCodexFallback(
        preferred: String?,
        registry: ProviderRegistry
    ) -> String? {
        if let id = firstHealthyAgentProviderId(preferred: preferred, registry: registry) {
            return id
        }
        if isHealthyAgentProvider(id: "codex-cli", registry: registry) {
            return "codex-cli"
        }
        return nil
    }

    /// Plan build requires Agent-compatible providers (CLI and API with tool support).
    static func isPlanBuildExecutionCapableProvider(id: String?, registry: ProviderRegistry) -> Bool {
        guard let id else { return false }
        guard isUserSelectableRealProvider(id: id) else { return false }
        guard registry.provider(for: id) != nil else { return false }
        return isAgentCompatibleProvider(id: id)
    }

    static let preferredIDEProviderIds = [
        "openai-api",
        "anthropic-api",
        "google-api",
        "openrouter-api",
        "minimax-api",
        "grok-api"
    ]

    static func isIDEProvider(id: String?) -> Bool {
        guard let id else { return false }
        return id.hasSuffix("-api")
    }

    static func preferredIDEProvider(in registry: ProviderRegistry) -> String {
        if let selected = registry.selectedProviderId,
           isIDEProvider(id: selected),
           isRegisteredProvider(id: selected, registry: registry) {
            return selected
        }

        for id in preferredIDEProviderIds
        where isRegisteredProvider(id: id, registry: registry) {
            return id
        }

        if let anyAPI = registry.providers.first(where: { isIDEProvider(id: $0.id) }) {
            return anyAPI.id
        }

        if let selected = registry.selectedProviderId, isIDEProvider(id: selected) {
            return selected
        }

        for id in preferredIDEProviderIds where registry.provider(for: id) != nil {
            return id
        }

        if let anyAPI = registry.providers.first(where: { isIDEProvider(id: $0.id) }) {
            return anyAPI.id
        }
        return "openai-api"
    }
}
