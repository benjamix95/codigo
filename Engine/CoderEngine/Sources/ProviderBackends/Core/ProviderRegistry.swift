import Foundation

/// Registry of available LLM providers
public final class ProviderRegistry: ObservableObject {
    @Published public private(set) var providers: [LLMProvider] = []
    @Published public var selectedProviderId: String? {
        didSet {
            if let id = selectedProviderId, !id.isEmpty {
                UserDefaults.standard.set(id, forKey: "lastUsedProviderId")
            }
        }
    }
    private var providerIndex: [String: LLMProvider] = [:]

    public init() {}

    /// The last provider the user selected (persisted across launches).
    public var lastUsedProviderId: String? {
        UserDefaults.standard.string(forKey: "lastUsedProviderId")
    }

    public func register(_ provider: LLMProvider) {
        guard providerIndex[provider.id] == nil else { return }
        providers.append(provider)
        providerIndex[provider.id] = provider
        if selectedProviderId == nil {
            // Restore last used provider if available, otherwise use first
            if let lastUsed = lastUsedProviderId, lastUsed == provider.id {
                selectedProviderId = lastUsed
            } else if selectedProviderId == nil && providers.count == 1 {
                selectedProviderId = provider.id
            }
        }
    }
    
    public func unregister(id: String) {
        providers.removeAll { $0.id == id }
        providerIndex.removeValue(forKey: id)
        if selectedProviderId == id {
            selectedProviderId = providers.first?.id
        }
    }
    
    public func provider(for id: String) -> LLMProvider? {
        providerIndex[id]
    }
    
    public var selectedProvider: LLMProvider? {
        guard let id = selectedProviderId else { return nil }
        return provider(for: id)
    }
}
