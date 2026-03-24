import Foundation

/// Circuit breaker leggero per ProviderBackends API.
///
/// Protegge i provider da retry durante interruzioni prolungate.
/// - `closed`: chiamate normali, failures contate
/// - `open`: chiamate rifiutate, cooldown attivo
/// - `halfOpen`: singola chiamata di probe ammessa
public actor ProviderCircuitBreaker {

    // MARK: - Types

    public enum Phase: String, Sendable {
        case closed
        case open
        case halfOpen
    }

    public struct Configuration: Sendable {
        public let maxConsecutiveFailures: Int
        public let cooldownSeconds: TimeInterval
        public let maxCooldownSeconds: TimeInterval
        public let halfOpenTimeoutSeconds: TimeInterval

        public init(
            maxConsecutiveFailures: Int = 5,
            cooldownSeconds: TimeInterval = 30,
            maxCooldownSeconds: TimeInterval = 120,
            halfOpenTimeoutSeconds: TimeInterval = 15
        ) {
            self.maxConsecutiveFailures = max(1, maxConsecutiveFailures)
            self.cooldownSeconds = max(1, cooldownSeconds)
            self.maxCooldownSeconds = max(cooldownSeconds, maxCooldownSeconds)
            self.halfOpenTimeoutSeconds = max(5, halfOpenTimeoutSeconds)
        }

        public static let `default` = Configuration()
    }

    public enum CallDecision: Sendable {
        case allow
        case reject(retryAfterSeconds: TimeInterval)
    }

    // MARK: - State

    private let providerId: String
    private let config: Configuration

    private var phase: Phase = .closed
    private var consecutiveFailures: Int = 0
    private var lastFailureAt: Date?
    private var currentCooldown: TimeInterval
    private var halfOpenEnteredAt: Date?

    // MARK: - Init

    public init(providerId: String, config: Configuration = .default) {
        self.providerId = providerId
        self.config = config
        self.currentCooldown = config.cooldownSeconds
    }

    // MARK: - Public API

    /// Verifica se la chiamata può procedere.
    public func shouldAllow(now: Date = Date()) -> CallDecision {
        switch phase {
        case .closed:
            return .allow

        case .open:
            guard let lastFailure = lastFailureAt else {
                transitionToClosed()
                return .allow
            }
            let elapsed = now.timeIntervalSince(lastFailure)
            if elapsed >= currentCooldown {
                phase = .halfOpen
                halfOpenEnteredAt = now
                return .allow
            }
            return .reject(retryAfterSeconds: currentCooldown - elapsed)

        case .halfOpen:
            if let entered = halfOpenEnteredAt {
                let elapsed = now.timeIntervalSince(entered)
                if elapsed > config.halfOpenTimeoutSeconds {
                    tripOpen(now: now)
                    return .reject(retryAfterSeconds: currentCooldown)
                }
            }
            return .allow
        }
    }

    /// Registra successo: resetta il circuit breaker.
    public func recordSuccess() {
        transitionToClosed()
    }

    /// Registra fallimento: incrementa contatore, eventualmente trip.
    public func recordFailure(now: Date = Date()) {
        consecutiveFailures += 1
        lastFailureAt = now

        switch phase {
        case .closed:
            if consecutiveFailures >= config.maxConsecutiveFailures {
                tripOpen(now: now)
            }
        case .halfOpen:
            let newCooldown = min(currentCooldown * 2, config.maxCooldownSeconds)
            currentCooldown = newCooldown
            phase = .open
            halfOpenEnteredAt = nil
        case .open:
            break
        }
    }

    /// Stato corrente per diagnostica.
    public var currentPhase: Phase { phase }
    public var failureCount: Int { consecutiveFailures }

    // MARK: - Private

    private func transitionToClosed() {
        phase = .closed
        consecutiveFailures = 0
        lastFailureAt = nil
        currentCooldown = config.cooldownSeconds
        halfOpenEnteredAt = nil
    }

    private func tripOpen(now: Date) {
        phase = .open
        lastFailureAt = now
        halfOpenEnteredAt = nil
    }
}
