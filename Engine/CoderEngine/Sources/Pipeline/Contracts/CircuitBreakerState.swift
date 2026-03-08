import Foundation

// MARK: - CircuitBreakerState

/// Stato persistente del circuit breaker (§6.11).
public struct CircuitBreakerState: Codable, Sendable, Equatable {
    public var jobId: String
    public var state: CircuitBreakerPhase
    public var consecutiveFailures: Int
    public var totalFailures: Int
    public var totalTasks: Int
    public var failureRatePercent: Double
    public var lastFailureAt: Date?
    public var trippedAt: Date?
    public var cooldownMs: Int
    public var probesSinceHalfOpen: Int

    public init(
        jobId: String,
        state: CircuitBreakerPhase = .closed,
        consecutiveFailures: Int = 0,
        totalFailures: Int = 0,
        totalTasks: Int = 0,
        failureRatePercent: Double = 0,
        lastFailureAt: Date? = nil,
        trippedAt: Date? = nil,
        cooldownMs: Int = 30_000,
        probesSinceHalfOpen: Int = 0
    ) {
        self.jobId = jobId
        self.state = state
        self.consecutiveFailures = consecutiveFailures
        self.totalFailures = totalFailures
        self.totalTasks = totalTasks
        self.failureRatePercent = failureRatePercent
        self.lastFailureAt = lastFailureAt
        self.trippedAt = trippedAt
        self.cooldownMs = cooldownMs
        self.probesSinceHalfOpen = probesSinceHalfOpen
    }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case state
        case consecutiveFailures = "consecutive_failures"
        case totalFailures = "total_failures"
        case totalTasks = "total_tasks"
        case failureRatePercent = "failure_rate_percent"
        case lastFailureAt = "last_failure_at"
        case trippedAt = "tripped_at"
        case cooldownMs = "cooldown_ms"
        case probesSinceHalfOpen = "probes_since_half_open"
    }

    /// Calcola failure rate corrente.
    public var computedFailureRate: Double {
        guard totalTasks > 0 else { return 0 }
        return (Double(totalFailures) / Double(totalTasks)) * 100.0
    }

    /// Verifica se il circuit breaker dovrebbe scattare (§17.1).
    /// Disabilitato per job con < 5 task.
    public func shouldTrip(budget: ErrorBudget) -> Bool {
        guard totalTasks >= 5 else { return false }
        return computedFailureRate > Double(budget.maxFailedTasksPercent)
            || consecutiveFailures >= budget.maxConsecutiveFailures
    }

    /// Error budget rimanente (§17.2).
    public func errorBudgetRemaining(budget: ErrorBudget) -> Double {
        Double(budget.maxFailedTasksPercent) - computedFailureRate
    }

    /// Warning se budget < 10% (§17.2).
    public func isErrorBudgetLow(budget: ErrorBudget) -> Bool {
        errorBudgetRemaining(budget: budget) < 10
    }
}

extension CircuitBreakerState: PipelineValidatable {
    public func validate() throws {
        let c = "CircuitBreakerState"
        try PipelineValidationHelpers.requireNonEmpty(jobId, field: "job_id", contract: c)
        try PipelineValidationHelpers.requireRange(
            cooldownMs, range: 1_000...300_000,
            field: "cooldown_ms", contract: c
        )
        if consecutiveFailures < 0 {
            throw PipelineValidationError.valueOutOfRange(
                field: "consecutive_failures", contract: c,
                value: "\(consecutiveFailures)", range: "0...∞"
            )
        }
    }
}
