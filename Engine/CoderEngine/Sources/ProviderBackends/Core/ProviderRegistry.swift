import Foundation

/// Registry of available LLM providers
public final class ProviderRegistry: ObservableObject {
    @Published public private(set) var providers: [LLMProvider] = []
    @Published public var selectedProviderId: String?
    private var providerIndex: [String: LLMProvider] = [:]
    
    public init() {}
    
    public func register(_ provider: LLMProvider) {
        guard providerIndex[provider.id] == nil else { return }
        providers.append(provider)
        providerIndex[provider.id] = provider
        if selectedProviderId == nil {
            selectedProviderId = provider.id
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
