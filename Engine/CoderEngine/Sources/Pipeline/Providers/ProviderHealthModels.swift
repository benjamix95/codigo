import Foundation

// MARK: - HealthProbeResult

/// Risultato di una singola probe verso un provider (§14.4).
public struct HealthProbeResult: Sendable, Equatable {
    public let providerId: String
    public let success: Bool
    public let latencyMs: Double
    public let timestamp: Date
    public let errorMessage: String?

    public init(
        providerId: String,
        success: Bool,
        latencyMs: Double = 0,
        timestamp: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.providerId = providerId
        self.success = success
        self.latencyMs = latencyMs
        self.timestamp = timestamp
        self.errorMessage = errorMessage
    }
}

// MARK: - HealthProbeDelegate

/// Protocollo per eseguire la probe reale verso un provider.
/// Permette di mockare negli unit test.
public protocol HealthProbeDelegate: Sendable {
    func probe(
        providerId: String,
        timeoutMs: Int
    ) async -> HealthProbeResult
}

// MARK: - HealthCheckerDelegate

/// Protocollo per notifiche di cambio stato (per EventBus integration).
public protocol HealthCheckerDelegate: Sendable {
    func onProviderHealthChanged(
        providerId: String,
        oldStatus: ProviderHealthStatus,
        newStatus: ProviderHealthStatus
    ) async

    func onFallbackTriggered(
        unhealthyProviderId: String
    ) async
}

// MARK: - ProviderHealthState

/// Stato interno di health tracking per singolo provider.
public struct ProviderHealthState: Sendable, Equatable {
    public var providerId: String
    public var healthStatus: ProviderHealthStatus
    public var consecutiveFailures: Int
    public var consecutiveSuccessesSinceRecovery: Int
    public var lastProbeTime: Date?
    public var lastProbeSuccess: Bool?
    public var errorRateWindow: [Bool]
    public var totalProbes: Int
    public var totalFailures: Int

    public init(
        providerId: String,
        healthStatus: ProviderHealthStatus = .healthy,
        consecutiveFailures: Int = 0,
        consecutiveSuccessesSinceRecovery: Int = 0,
        lastProbeTime: Date? = nil,
        lastProbeSuccess: Bool? = nil,
        errorRateWindow: [Bool] = [],
        totalProbes: Int = 0,
        totalFailures: Int = 0
    ) {
        self.providerId = providerId
        self.healthStatus = healthStatus
        self.consecutiveFailures = consecutiveFailures
        self.consecutiveSuccessesSinceRecovery = consecutiveSuccessesSinceRecovery
        self.lastProbeTime = lastProbeTime
        self.lastProbeSuccess = lastProbeSuccess
        self.errorRateWindow = errorRateWindow
        self.totalProbes = totalProbes
        self.totalFailures = totalFailures
    }

    /// Error rate calcolata su finestra sliding (§6.5).
    public var errorRate: Double {
        guard !errorRateWindow.isEmpty else { return 0 }
        let failures = errorRateWindow.filter { !$0 }.count
        return Double(failures) / Double(errorRateWindow.count)
    }
}
