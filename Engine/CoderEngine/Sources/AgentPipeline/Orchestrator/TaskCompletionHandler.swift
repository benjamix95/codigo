import Foundation

// MARK: - CompletionAction

/// Azione risultante dalla gestione del completamento di un task (§5.5).
public enum CompletionAction: Sendable, Equatable {
    case scheduleNextAgent(taskId: String, role: AgentRole)
    case scheduleFixRound(taskId: String, reason: String)
    case transitionToValidation(taskId: String)
    case blockTask(taskId: String, reason: String)
    case retryTask(taskId: String, delayMs: Int)
    case failTask(taskId: String, reason: String)
    case abortJob(reason: String)
    case continueNormally
}

// MARK: - TaskCompletionHandler

/// Gestisce i risultati dei task completati (§5.5).
///
/// Responsabilità:
/// - Routing per ruolo agente (explorer → coder → reviewer → testWriter → docWriter)
/// - Gestione successi con schedule del prossimo agente
/// - Gestione fallimenti con retry policy
/// - Integrazione con error budget e circuit breaker (via return value)
///
/// Non modifica direttamente lo stato: restituisce `CompletionAction`
/// che l'orchestrator main loop interpreta.
public struct TaskCompletionHandler: Sendable {

    /// Massimo tentativi di retry per task.
    public let maxRetryAttempts: Int
    /// Delay base per retry (ms).
    public let retryBaseDelayMs: Int
    /// Delay massimo per retry (ms).
    public let retryMaxDelayMs: Int
    /// Seed per jitter deterministico (§5.11).
    public let jitterSeed: UInt64

    public init(
        maxRetryAttempts: Int = 3,
        retryBaseDelayMs: Int = 1000,
        retryMaxDelayMs: Int = 30_000,
        jitterSeed: UInt64 = UInt64(Date().timeIntervalSince1970.bitPattern &>> 16)
    ) {
        self.maxRetryAttempts = maxRetryAttempts
        self.retryBaseDelayMs = retryBaseDelayMs
        self.retryMaxDelayMs = retryMaxDelayMs
        self.jitterSeed = jitterSeed
    }

    // MARK: - Handle Success

    /// Gestisce un risultato di successo, restituendo la prossima azione.
    public func handleSuccess(
        result: WorkerTaskResult,
        task: TaskNode,
        hasCriticalFindings: Bool = false,
        testsPass: Bool = true,
        shouldInvokeDocWriter: Bool = false
    ) -> CompletionAction {
        let baseAction: CompletionAction
        switch result.agentRole {
        case .explorer:
            baseAction = .scheduleNextAgent(taskId: task.taskId, role: .coder)

        case .coder, .debugger:
            baseAction = .scheduleNextAgent(taskId: task.taskId, role: .reviewer)

        case .reviewer, .bugHunter:
            if hasCriticalFindings {
                baseAction = .scheduleFixRound(
                    taskId: task.taskId,
                    reason: "Critical findings detected in review"
                )
            } else {
                baseAction = .scheduleNextAgent(taskId: task.taskId, role: .testWriter)
            }

        case .testWriter:
            if !testsPass {
                baseAction = .scheduleFixRound(
                    taskId: task.taskId,
                    reason: "Tests failed"
                )
            } else if shouldInvokeDocWriter {
                baseAction = .scheduleNextAgent(taskId: task.taskId, role: .docWriter)
            } else {
                baseAction = .transitionToValidation(taskId: task.taskId)
            }

        case .docWriter:
            baseAction = .transitionToValidation(taskId: task.taskId)

        case .securityAuditor:
            if hasCriticalFindings {
                baseAction = .blockTask(
                    taskId: task.taskId,
                    reason: "Security vulnerabilities detected"
                )
            } else {
                baseAction = .continueNormally
            }

        case .planner:
            baseAction = .continueNormally
        }

        return adaptSuccessActionForExecutionStyle(
            baseAction,
            task: task
        )
    }

    // MARK: - Handle Failure

    /// Gestisce un risultato di fallimento, restituendo la prossima azione.
    public func handleFailure(
        result: WorkerTaskResult,
        task: TaskNode,
        consecutiveFailures: Int,
        errorBudget: ErrorBudget,
        totalTasks: Int,
        failedTaskCount: Int
    ) -> CompletionAction {
        if shouldTripCircuitBreaker(
            consecutiveFailures: consecutiveFailures,
            errorBudget: errorBudget,
            totalTasks: totalTasks,
            failedTaskCount: failedTaskCount
        ) {
            return .abortJob(reason: "Circuit breaker tripped — error budget exhausted")
        }

        let isRetryable = Self.isRetryableError(result.error)

        if isRetryable && task.attempts < task.maxAttempts {
            let delay = calculateRetryDelay(attempt: task.attempts + 1)
            return .retryTask(taskId: task.taskId, delayMs: delay)
        }

        return .failTask(
            taskId: task.taskId,
            reason: result.error ?? "Unknown error"
        )
    }

    // MARK: - DocWriter Rules (§6.14)

    /// Determina se il docWriter deve essere invocato per un task.
    public func shouldInvokeDocWriter(task: TaskNode, riskScore: Double = 0) -> Bool {
        if task.taskType == .feature && task.fileScope.count > 0 {
            return true
        }
        if riskScore > 0.5 {
            return true
        }
        if task.fileScope.count > 5 {
            return true
        }
        if task.taskType == .test {
            return false
        }
        return false
    }

    // MARK: - Retry Logic

    /// Calcola il delay di retry con exponential backoff + deterministic jitter (§5.11).
    public func calculateRetryDelay(attempt: Int) -> Int {
        let exp = Double(retryBaseDelayMs) * pow(2.0, Double(attempt - 1))
        let jitter = deterministicJitter(seed: jitterSeed, attempt: attempt)
        let raw = Int(exp) + jitter
        return min(raw, retryMaxDelayMs)
    }

    // MARK: - Circuit Breaker Check

    /// Verifica se il circuit breaker dovrebbe scattare (§5.10).
    public func shouldTripCircuitBreaker(
        consecutiveFailures: Int,
        errorBudget: ErrorBudget,
        totalTasks: Int,
        failedTaskCount: Int
    ) -> Bool {
        if totalTasks < 5 {
            return false
        }

        if consecutiveFailures >= errorBudget.maxConsecutiveFailures {
            return true
        }

        let failureRate = Double(failedTaskCount) / Double(totalTasks) * 100.0
        if failureRate > Double(errorBudget.maxFailedTasksPercent) {
            return true
        }

        return false
    }

    // MARK: - Private

    private func adaptSuccessActionForExecutionStyle(
        _ action: CompletionAction,
        task: TaskNode
    ) -> CompletionAction {
        guard task.executionStyle.isDirectExecution else {
            return action
        }

        switch action {
        case .scheduleNextAgent:
            return .transitionToValidation(taskId: task.taskId)
        case .continueNormally:
            return .transitionToValidation(taskId: task.taskId)
        case .scheduleFixRound, .transitionToValidation, .blockTask,
             .retryTask, .failTask, .abortJob:
            return action
        }
    }

    /// Jitter deterministico basato su seed e attempt (§5.11).
    private func deterministicJitter(seed: UInt64, attempt: Int) -> Int {
        var hash = seed &* 6_364_136_223_846_793_005 &+ UInt64(attempt) &* 1_442_695_040_888_963_407
        hash ^= hash >> 33
        hash &*= 0xff51afd7ed558ccd
        hash ^= hash >> 33
        let maxJitter = max(1, retryBaseDelayMs / 4)
        return Int(hash % UInt64(maxJitter))
    }

    /// Determina se un errore è retryable.
    static func isRetryableError(_ error: String?) -> Bool {
        guard let err = error?.lowercased() else { return true }
        let nonRetryable = [
            "validation_error",
            "invalid_envelope",
            "security_block",
            "permission_denied"
        ]
        return !nonRetryable.contains(where: { err.contains($0) })
    }
}
