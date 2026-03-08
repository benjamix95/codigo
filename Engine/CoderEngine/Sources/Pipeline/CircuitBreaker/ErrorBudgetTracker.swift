import Foundation

// MARK: - BudgetAlert

/// Allarme emesso dall'ErrorBudgetTracker (§17.2).
public enum BudgetAlert: Sendable, Equatable {
    case budgetLow(remaining: Double)
    case budgetExhausted(failureRate: Double)
    case budgetRecovered(remaining: Double)
}

// MARK: - TaskFailureRecord

/// Record di un singolo task per il tracking del budget.
public struct TaskFailureRecord: Sendable, Equatable {
    public let taskId: String
    public let taskType: TaskType
    public let isCriticalPath: Bool
    public let succeeded: Bool
    public let timestamp: Date

    public init(
        taskId: String,
        taskType: TaskType = .feature,
        isCriticalPath: Bool = false,
        succeeded: Bool,
        timestamp: Date = Date()
    ) {
        self.taskId = taskId
        self.taskType = taskType
        self.isCriticalPath = isCriticalPath
        self.succeeded = succeeded
        self.timestamp = timestamp
    }
}

// MARK: - ErrorBudgetSnapshot

/// Snapshot leggibile del budget in tempo reale (§17.2 regola 3).
public struct ErrorBudgetSnapshot: Sendable, Equatable {
    public let totalTasks: Int
    public let totalWeightedFailures: Int
    public let failureRatePercent: Double
    public let budgetMaxPercent: Int
    public let budgetRemainingPercent: Double
    public let isLow: Bool
    public let isExhausted: Bool
    public let consecutiveFailures: Int
    public let maxConsecutiveFailures: Int

    public init(
        totalTasks: Int,
        totalWeightedFailures: Int,
        failureRatePercent: Double,
        budgetMaxPercent: Int,
        budgetRemainingPercent: Double,
        isLow: Bool,
        isExhausted: Bool,
        consecutiveFailures: Int,
        maxConsecutiveFailures: Int
    ) {
        self.totalTasks = totalTasks
        self.totalWeightedFailures = totalWeightedFailures
        self.failureRatePercent = failureRatePercent
        self.budgetMaxPercent = budgetMaxPercent
        self.budgetRemainingPercent = budgetRemainingPercent
        self.isLow = isLow
        self.isExhausted = isExhausted
        self.consecutiveFailures = consecutiveFailures
        self.maxConsecutiveFailures = maxConsecutiveFailures
    }
}

// MARK: - ErrorBudgetTracker

/// Tracker dell'error budget con alerting (§17.2, §17.3).
///
/// Formula: `remaining = max_percent - (weighted_failures / total_tasks * 100)`
///
/// Regole peso (§17.3):
/// - `critical_path: true` → peso 2
/// - `test` o `docs` → peso 0 (non contano)
/// - tutti gli altri → peso 1
///
/// Alerting:
/// - `remaining < 10%` → warning `error_budget_low`
/// - `remaining <= 0%` → trigger circuit breaker
public struct ErrorBudgetTracker: Sendable {

    private let budget: ErrorBudget

    public static let lowBudgetThreshold: Double = 10.0

    public init(budget: ErrorBudget = ErrorBudget()) {
        self.budget = budget
    }

    // MARK: - Weight Calculation

    /// Calcola il peso di un failure per tipo task (§17.3).
    public func failureWeight(
        taskType: TaskType,
        isCriticalPath: Bool
    ) -> Int {
        if isCriticalPath { return 2 }
        switch taskType {
        case .test, .docs: return 0
        case .feature, .bugfix, .refactor: return 1
        }
    }

    // MARK: - Budget Calculation

    /// Calcola la failure rate pesata.
    public func weightedFailureRate(
        totalTasks: Int,
        weightedFailures: Int
    ) -> Double {
        guard totalTasks > 0 else { return 0 }
        return (Double(weightedFailures) / Double(totalTasks)) * 100.0
    }

    /// Calcola il budget rimanente.
    public func budgetRemaining(
        totalTasks: Int,
        weightedFailures: Int
    ) -> Double {
        let rate = weightedFailureRate(
            totalTasks: totalTasks,
            weightedFailures: weightedFailures
        )
        return Double(budget.maxFailedTasksPercent) - rate
    }

    /// Verifica se il budget è basso (< 10% rimanente).
    public func isBudgetLow(
        totalTasks: Int,
        weightedFailures: Int
    ) -> Bool {
        let remaining = budgetRemaining(
            totalTasks: totalTasks,
            weightedFailures: weightedFailures
        )
        return remaining < Self.lowBudgetThreshold && remaining >= 0
    }

    /// Verifica se il budget è esaurito (< 0%, coerente con `CircuitBreakerState.shouldTrip`
    /// che usa `>` stretto su `failureRate > maxPercent`).
    public func isBudgetExhausted(
        totalTasks: Int,
        weightedFailures: Int
    ) -> Bool {
        budgetRemaining(
            totalTasks: totalTasks,
            weightedFailures: weightedFailures
        ) < 0
    }

    /// Verifica se il consecutive failures trigger è superato.
    public func isConsecutiveThresholdBreached(
        consecutiveFailures: Int
    ) -> Bool {
        consecutiveFailures >= budget.maxConsecutiveFailures
    }

    /// Verifica se il circuit breaker dovrebbe scattare (§17.1).
    /// Disabilitato per job con < 5 task.
    public func shouldTrip(
        totalTasks: Int,
        weightedFailures: Int,
        consecutiveFailures: Int
    ) -> Bool {
        guard totalTasks >= 5 else { return false }
        return isBudgetExhausted(
            totalTasks: totalTasks,
            weightedFailures: weightedFailures
        ) || isConsecutiveThresholdBreached(
            consecutiveFailures: consecutiveFailures
        )
    }

    // MARK: - Snapshot

    /// Genera uno snapshot leggibile del budget (§17.2 regola 3).
    public func snapshot(
        totalTasks: Int,
        weightedFailures: Int,
        consecutiveFailures: Int
    ) -> ErrorBudgetSnapshot {
        let rate = weightedFailureRate(
            totalTasks: totalTasks,
            weightedFailures: weightedFailures
        )
        let remaining = Double(budget.maxFailedTasksPercent) - rate

        return ErrorBudgetSnapshot(
            totalTasks: totalTasks,
            totalWeightedFailures: weightedFailures,
            failureRatePercent: rate,
            budgetMaxPercent: budget.maxFailedTasksPercent,
            budgetRemainingPercent: remaining,
            isLow: remaining < Self.lowBudgetThreshold && remaining >= 0,
            isExhausted: remaining < 0,
            consecutiveFailures: consecutiveFailures,
            maxConsecutiveFailures: budget.maxConsecutiveFailures
        )
    }

    // MARK: - Alert Check

    /// Determina quale alert emettere (se presente).
    public func checkAlert(
        totalTasks: Int,
        weightedFailures: Int
    ) -> BudgetAlert? {
        let remaining = budgetRemaining(
            totalTasks: totalTasks,
            weightedFailures: weightedFailures
        )

        if remaining < 0 {
            return .budgetExhausted(
                failureRate: weightedFailureRate(
                    totalTasks: totalTasks,
                    weightedFailures: weightedFailures
                )
            )
        }

        if remaining < Self.lowBudgetThreshold {
            return .budgetLow(remaining: remaining)
        }

        return nil
    }

    /// Calcola il failure weight cumulativo da una lista di record.
    public func computeWeightedFailures(
        from records: [TaskFailureRecord]
    ) -> Int {
        records.filter { !$0.succeeded }.reduce(0) { sum, record in
            sum + failureWeight(
                taskType: record.taskType,
                isCriticalPath: record.isCriticalPath
            )
        }
    }

    // MARK: - Config Access

    public var maxFailedTasksPercent: Int {
        budget.maxFailedTasksPercent
    }

    public var maxConsecutiveFailures: Int {
        budget.maxConsecutiveFailures
    }
}
