import Foundation

/// Registry dei provider LLM disponibili
public final class ProviderRegistry: ObservableObject {
    @Published public private(set) var providers: [LLMProvider] = []
    @Published public var selectedProviderId: String?
    
    public init() {}
    
    public func register(_ provider: LLMProvider) {
        if !providers.contains(where: { $0.id == provider.id }) {
            providers.append(provider)
            if selectedProviderId == nil {
                selectedProviderId = provider.id
            }
        }
    }
    
    public func unregister(id: String) {
        providers.removeAll { $0.id == id }
        if selectedProviderId == id {
            selectedProviderId = providers.first?.id
        }
    }
    
    public func provider(for id: String) -> LLMProvider? {
        providers.first { $0.id == id }
    }
    
    public var selectedProvider: LLMProvider? {
        guard let id = selectedProviderId else { return nil }
        return provider(for: id)
    }
}
