import Foundation

/// Registry globale dei circuit breaker per provider.
///
/// Ogni provider ottiene un'istanza unica tramite il proprio ID,
/// garantendo che lo stato del circuit breaker sia condiviso tra
/// tutte le chiamate allo stesso provider.
public actor ProviderCircuitBreakerRegistry {
    public static let shared = ProviderCircuitBreakerRegistry()

    private var breakers: [String: ProviderCircuitBreaker] = [:]

    /// Ottiene o crea il circuit breaker per un provider.
    public func breaker(
        for providerId: String,
        config: ProviderCircuitBreaker.Configuration = .default
    ) -> ProviderCircuitBreaker {
        if let existing = breakers[providerId] {
            return existing
        }
        let cb = ProviderCircuitBreaker(providerId: providerId, config: config)
        breakers[providerId] = cb
        return cb
    }

    /// Reset per testing.
    func resetAll() {
        breakers.removeAll()
    }
}
