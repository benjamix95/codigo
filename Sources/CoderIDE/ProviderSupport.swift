import CoderEngine

enum ProviderSupport {
    static let agentProviderIds = ["codex-cli", "claude-cli", "gemini-cli"]

    /// API providers that support Agent mode (tools, multi-turn, read_batch).
    static let agentApiProviderIds = [
        "openai-api",
        "anthropic-api",
        "google-api",
        "openrouter-api",
        "minimax-api",
        "grok-api"
    ]

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
        return (agentProviderIds + agentApiProviderIds).contains(id)
    }

    /// Build del piano richiede provider compatibili con Agent (CLI e API con tool support).
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
           registry.provider(for: selected)?.isAuthenticated() == true {
            return selected
        }

        for id in preferredIDEProviderIds
        where registry.provider(for: id)?.isAuthenticated() == true {
            return id
        }

        if let anyAPI = registry.providers.first(where: { isIDEProvider(id: $0.id) && $0.isAuthenticated() }) {
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
