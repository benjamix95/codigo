import CoderEngine

enum ProviderSupport {
    static let preferredIDEProviderIds = [
        "openai-api",
        "anthropic-api",
        "google-api",
        "openrouter-api",
        "minimax-api"
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
