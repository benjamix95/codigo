import Foundation

// MARK: - CircuitBreakerTransition

/// Risultato di una transizione del circuit breaker.
public enum CircuitBreakerTransition: Sendable, Equatable {
    case noChange
    case tripped(failureRate: Double, consecutive: Int, budgetRemaining: Double)
    case cooldownExpired
    case probeSucceeded
    case probeFailed(newCooldownMs: Int)
}

// MARK: - CircuitBreakerDelegate

/// Protocollo per notifiche di transizione (integrazione EventBus).
public protocol CircuitBreakerDelegate: Sendable {
    func onCircuitBreakerTripped(
        jobId: String,
        failureRate: Double,
        consecutiveFailures: Int,
        budgetRemaining: Double
    ) async

    func onCircuitBreakerRecovered(jobId: String) async

    func onErrorBudgetLow(
        jobId: String,
        remaining: Double
    ) async
}

// MARK: - CircuitBreaker

/// Circuit breaker con stati closed/open/half_open (§17.1).
///
/// Regole:
/// 1. `closed`: pipeline opera normalmente, failures vengono contate
/// 2. `closed → open`: quando failure_rate > budget OR consecutive >= max
/// 3. `open`: nessun nuovo task dispatched
/// 4. `open → half_open`: dopo cooldown_ms
/// 5. `half_open`: un solo task come probe
/// 6. probe success → `closed`; probe failure → `open` con cooldown raddoppiato
///    (max 60_000ms)
///
/// Job con < 5 task: circuit breaker disabilitato (§17.3).
public actor CircuitBreaker {

    private var internalState: CircuitBreakerState
    private let budget: ErrorBudget
    private let delegate: CircuitBreakerDelegate?

    public static let defaultCooldownMs = 30_000
    public static let maxCooldownMs = 60_000
    public static let minTasksForActivation = 5
    public static let maxProbeFailuresBeforeAbort = 3
    public static let probeTimeoutMs = 15_000

    private(set) var totalTrips: Int = 0
    private(set) var totalRecoveries: Int = 0
    private(set) var totalProbeAttempts: Int = 0

    public init(
        jobId: String,
        budget: ErrorBudget = ErrorBudget(),
        cooldownMs: Int = defaultCooldownMs,
        delegate: CircuitBreakerDelegate? = nil
    ) {
        self.internalState = CircuitBreakerState(
            jobId: jobId,
            state: .closed,
            cooldownMs: cooldownMs
        )
        self.budget = budget
        self.delegate = delegate
    }

    /// Inizializza da uno stato persistente esistente.
    public init(
        state: CircuitBreakerState,
        budget: ErrorBudget,
        delegate: CircuitBreakerDelegate? = nil
    ) {
        self.internalState = state
        self.budget = budget
        self.delegate = delegate
    }

    // MARK: - State Query

    public var state: CircuitBreakerState {
        internalState
    }

    public var phase: CircuitBreakerPhase {
        internalState.state
    }

    public var isOpen: Bool {
        internalState.state == .open
    }

    public var isClosed: Bool {
        internalState.state == .closed
    }

    public var isHalfOpen: Bool {
        internalState.state == .halfOpen
    }

    /// `true` se si possono dispatchare nuovi task normali.
    public var canDispatch: Bool {
        internalState.state == .closed
    }

    /// `true` se si può dispatchare un singolo probe task.
    /// Se il probe ha superato `probeTimeoutMs`, tratta come fallimento
    /// e torna in open per evitare stallo indefinito in half-open.
    public var canDispatchProbe: Bool {
        guard internalState.state == .halfOpen else { return false }
        // Safety: se half-open dura troppo, il probe è appeso → fallback a open
        if let trippedAt = internalState.trippedAt {
            let elapsed = Date().timeIntervalSince(trippedAt) * 1000
            if elapsed >= Double(Self.probeTimeoutMs) {
                return false
            }
        }
        return true
    }

    /// `true` se il CB è disabilitato (< 5 task).
    public var isDisabled: Bool {
        internalState.totalTasks < Self.minTasksForActivation
    }

    /// `true` se il job dovrebbe essere abortito (3 probe fallite).
    public var shouldAbortJob: Bool {
        internalState.probesSinceHalfOpen >= Self.maxProbeFailuresBeforeAbort
            && internalState.state == .open
    }

    // MARK: - Record Success

    /// Registra un task completato con successo (§5.5).
    public func recordSuccess() async -> CircuitBreakerTransition {
        internalState.totalTasks += 1
        internalState.consecutiveFailures = 0
        updateFailureRate()

        if internalState.state == .halfOpen {
            internalState.state = .closed
            internalState.trippedAt = nil
            internalState.probesSinceHalfOpen = 0
            internalState.cooldownMs = Self.defaultCooldownMs
            totalRecoveries += 1

            await delegate?.onCircuitBreakerRecovered(
                jobId: internalState.jobId
            )
            return .probeSucceeded
        }

        return .noChange
    }

    // MARK: - Record Failure

    /// Registra un task fallito (§5.5).
    public func recordFailure(
        taskType: TaskType = .feature,
        isCriticalPath: Bool = false
    ) async -> CircuitBreakerTransition {
        internalState.totalTasks += 1
        internalState.lastFailureAt = Date()

        let weight = failureWeight(
            taskType: taskType,
            isCriticalPath: isCriticalPath
        )
        internalState.totalFailures += weight
        internalState.consecutiveFailures += 1

        updateFailureRate()

        if internalState.state == .halfOpen {
            let newCooldown = min(
                internalState.cooldownMs * 2,
                Self.maxCooldownMs
            )
            internalState.state = .open
            internalState.trippedAt = Date()
            internalState.cooldownMs = newCooldown
            internalState.probesSinceHalfOpen += 1
            totalProbeAttempts += 1

            return .probeFailed(newCooldownMs: newCooldown)
        }

        if internalState.state == .open {
            return .noChange
        }

        if !isDisabled && internalState.shouldTrip(budget: budget) {
            let remaining = internalState.errorBudgetRemaining(
                budget: budget
            )
            internalState.state = .open
            internalState.trippedAt = Date()
            totalTrips += 1

            await delegate?.onCircuitBreakerTripped(
                jobId: internalState.jobId,
                failureRate: internalState.computedFailureRate,
                consecutiveFailures: internalState.consecutiveFailures,
                budgetRemaining: remaining
            )

            return .tripped(
                failureRate: internalState.computedFailureRate,
                consecutive: internalState.consecutiveFailures,
                budgetRemaining: remaining
            )
        }

        if internalState.isErrorBudgetLow(budget: budget) {
            await delegate?.onErrorBudgetLow(
                jobId: internalState.jobId,
                remaining: internalState.errorBudgetRemaining(
                    budget: budget
                )
            )
        }

        return .noChange
    }

    // MARK: - Cooldown Check

    /// Verifica se il cooldown è scaduto e transiziona a half_open (§17.1).
    public func checkCooldown(now: Date = Date()) -> CircuitBreakerTransition {
        guard internalState.state == .open,
              let trippedAt = internalState.trippedAt
        else {
            return .noChange
        }

        let elapsed = now.timeIntervalSince(trippedAt) * 1000
        if elapsed >= Double(internalState.cooldownMs) {
            internalState.state = .halfOpen
            return .cooldownExpired
        }

        return .noChange
    }

    /// Verifica se il probe in half-open è scaduto (§17.1 safety).
    /// Se half-open dura più di `probeTimeoutMs`, tratta come fallimento
    /// e transiziona back to open con cooldown raddoppiato.
    public func checkProbeTimeout(now: Date = Date()) -> CircuitBreakerTransition {
        guard internalState.state == .halfOpen,
              let trippedAt = internalState.trippedAt
        else {
            return .noChange
        }

        let elapsed = now.timeIntervalSince(trippedAt) * 1000
        if elapsed >= Double(Self.probeTimeoutMs) {
            let newCooldown = min(
                internalState.cooldownMs * 2,
                Self.maxCooldownMs
            )
            internalState.state = .open
            internalState.trippedAt = now
            internalState.cooldownMs = newCooldown
            internalState.probesSinceHalfOpen += 1
            totalProbeAttempts += 1
            return .probeFailed(newCooldownMs: newCooldown)
        }

        return .noChange
    }

    /// Millisecondi rimanenti prima della scadenza del cooldown.
    public func remainingCooldownMs(now: Date = Date()) -> Int {
        guard internalState.state == .open,
              let trippedAt = internalState.trippedAt
        else {
            return 0
        }

        let elapsed = now.timeIntervalSince(trippedAt) * 1000
        return max(0, internalState.cooldownMs - Int(elapsed))
    }

    // MARK: - Error Budget Query

    public var errorBudgetRemaining: Double {
        internalState.errorBudgetRemaining(budget: budget)
    }

    public var isErrorBudgetLow: Bool {
        internalState.isErrorBudgetLow(budget: budget)
    }

    public var failureRatePercent: Double {
        internalState.computedFailureRate
    }

    // MARK: - Stats

    public var stats: (trips: Int, recoveries: Int, probes: Int) {
        (totalTrips, totalRecoveries, totalProbeAttempts)
    }

    // MARK: - Private

    /// Peso del failure per task type (§17.3).
    private func failureWeight(
        taskType: TaskType,
        isCriticalPath: Bool
    ) -> Int {
        if isCriticalPath { return 2 }
        switch taskType {
        case .test, .docs: return 0
        case .feature, .bugfix, .refactor: return 1
        }
    }

    private func updateFailureRate() {
        internalState.failureRatePercent =
            internalState.computedFailureRate
    }
}
