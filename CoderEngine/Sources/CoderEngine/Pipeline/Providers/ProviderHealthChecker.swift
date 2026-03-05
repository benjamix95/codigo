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

// MARK: - ProviderHealthChecker

/// Health checker con probe periodico e recovery (§14.4).
///
/// Invarianti:
/// 1. Provider `unhealthy` MUST essere escluso dal routing
/// 2. Recovery richiede `healthy_threshold` probe consecutive con successo
/// 3. Health check MUST NON contare come retry nel budget task
public actor ProviderHealthChecker {

    private let probeDelegate: HealthProbeDelegate
    private let notificationDelegate: HealthCheckerDelegate?
    private let config: HealthCheckConfig

    private var providerStates: [String: ProviderHealthState] = [:]

    static let maxErrorRateWindowSize = 60

    private(set) var totalProbesExecuted: Int = 0
    private(set) var totalStatusChanges: Int = 0
    private(set) var totalFallbacksTriggered: Int = 0

    public init(
        probeDelegate: HealthProbeDelegate,
        notificationDelegate: HealthCheckerDelegate? = nil,
        config: HealthCheckConfig = HealthCheckConfig()
    ) {
        self.probeDelegate = probeDelegate
        self.notificationDelegate = notificationDelegate
        self.config = config
    }

    // MARK: - Registration

    /// Registra un provider per il monitoraggio.
    public func registerProvider(_ entry: ProviderCapabilityEntry) {
        providerStates[entry.providerId] = ProviderHealthState(
            providerId: entry.providerId,
            healthStatus: entry.healthStatus
        )
    }

    /// Registra tutti i provider dalla matrice.
    public func registerAll(from matrix: ProviderCapabilityMatrix) {
        for provider in matrix.providers {
            registerProvider(provider)
        }
    }

    // MARK: - Probe Cycle

    /// Esegue un ciclo di probe su tutti i provider registrati (§14.4).
    public func runProbeCycle() async {
        for providerId in providerStates.keys {
            await probeProvider(providerId)
        }
    }

    /// Esegue una probe su un singolo provider (§14.4).
    public func probeProvider(_ providerId: String) async {
        guard var state = providerStates[providerId] else { return }

        let result = await probeDelegate.probe(
            providerId: providerId,
            timeoutMs: config.probeTimeoutMs
        )

        totalProbesExecuted += 1
        state.totalProbes += 1
        state.lastProbeTime = result.timestamp
        state.lastProbeSuccess = result.success

        appendToErrorWindow(&state, success: result.success)

        let oldStatus = state.healthStatus

        if result.success {
            state.consecutiveFailures = 0
            state = handleProbeSuccess(state: state)
        } else {
            state.totalFailures += 1
            state.consecutiveSuccessesSinceRecovery = 0
            state = handleProbeFailure(state: state)
        }

        let newStatus = state.healthStatus
        providerStates[providerId] = state

        if oldStatus != newStatus {
            totalStatusChanges += 1
            await notificationDelegate?.onProviderHealthChanged(
                providerId: providerId,
                oldStatus: oldStatus,
                newStatus: newStatus
            )

            if newStatus == .unhealthy && config.autoFallbackOnUnhealthy {
                totalFallbacksTriggered += 1
                await notificationDelegate?.onFallbackTriggered(
                    unhealthyProviderId: providerId
                )
            }
        }
    }

    // MARK: - State Transitions

    /// Gestisce probe riuscita (§14.4).
    private func handleProbeSuccess(
        state: ProviderHealthState
    ) -> ProviderHealthState {
        var updated = state

        switch state.healthStatus {
        case .healthy:
            break

        case .unhealthy:
            updated.healthStatus = .recovering
            updated.consecutiveSuccessesSinceRecovery = 1

        case .recovering:
            updated.consecutiveSuccessesSinceRecovery += 1
            if updated.consecutiveSuccessesSinceRecovery
                >= config.healthyThreshold
            {
                updated.healthStatus = .healthy
                updated.consecutiveSuccessesSinceRecovery = 0
            }
        }

        return updated
    }

    /// Gestisce probe fallita (§14.4).
    private func handleProbeFailure(
        state: ProviderHealthState
    ) -> ProviderHealthState {
        var updated = state
        updated.consecutiveFailures += 1

        switch state.healthStatus {
        case .healthy:
            if updated.consecutiveFailures >= config.unhealthyThreshold {
                updated.healthStatus = .unhealthy
            }

        case .recovering:
            updated.healthStatus = .unhealthy
            updated.consecutiveSuccessesSinceRecovery = 0

        case .unhealthy:
            break
        }

        return updated
    }

    // MARK: - Error Rate Window

    private func appendToErrorWindow(
        _ state: inout ProviderHealthState,
        success: Bool
    ) {
        state.errorRateWindow.append(success)
        if state.errorRateWindow.count > Self.maxErrorRateWindowSize {
            state.errorRateWindow.removeFirst()
        }
    }

    // MARK: - Query

    /// Stato corrente di un provider.
    public func state(
        for providerId: String
    ) -> ProviderHealthState? {
        providerStates[providerId]
    }

    /// Tutti gli stati dei provider.
    public var allStates: [String: ProviderHealthState] {
        providerStates
    }

    /// Provider ID attualmente healthy.
    public var healthyProviderIds: [String] {
        providerStates
            .filter { $0.value.healthStatus != .unhealthy }
            .map(\.key)
    }

    /// Provider ID attualmente unhealthy.
    public var unhealthyProviderIds: [String] {
        providerStates
            .filter { $0.value.healthStatus == .unhealthy }
            .map(\.key)
    }

    /// Verifica se un provider è disponibile per il routing (§14.4 regola 1).
    public func isAvailableForRouting(
        _ providerId: String
    ) -> Bool {
        guard let state = providerStates[providerId] else {
            return false
        }
        return state.healthStatus != .unhealthy
    }

    /// Aggiorna la matrice provider con gli stati health attuali.
    public func applyHealthStates(
        to matrix: ProviderCapabilityMatrix
    ) -> ProviderCapabilityMatrix {
        var updated = matrix
        for i in updated.providers.indices {
            let pid = updated.providers[i].providerId
            if let healthState = providerStates[pid] {
                updated.providers[i].healthStatus =
                    healthState.healthStatus
                updated.providers[i].errorRateLastHour =
                    healthState.errorRate
                updated.providers[i].lastHealthCheck =
                    healthState.lastProbeTime
            }
        }
        return updated
    }

    /// Statistiche aggregate.
    public var stats: (
        probes: Int, statusChanges: Int, fallbacks: Int
    ) {
        (totalProbesExecuted, totalStatusChanges, totalFallbacksTriggered)
    }

    /// Numero provider registrati.
    public var registeredCount: Int {
        providerStates.count
    }
}
