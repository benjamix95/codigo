import Foundation

// MARK: - PipelineUIEvent

/// Eventi emessi dalla pipeline verso il layer UI.
/// Ogni caso trasporta dati minimi, Sendable, adatti al consumo da MainActor.
public enum PipelineUIEvent: Sendable {

    // MARK: Job lifecycle

    case jobStarted(JobStartedPayload)
    case jobCompleted(JobCompletedPayload)
    case jobFailed(JobFailedPayload)

    // MARK: Task lifecycle

    case taskStarted(TaskStartedPayload)
    case taskCompleted(TaskCompletedPayload)
    case taskFailed(TaskFailedPayload)

    // MARK: Streaming

    case textDelta(TextDeltaPayload)
    case textReplace(TextReplacePayload)

    // MARK: Raw agent events

    case rawEvent(RawEventPayload)

    // MARK: Patch & files

    case patchApplied(PatchAppliedPayload)
    case rollbackTriggered(RollbackPayload)

    // MARK: Review

    case reviewFinding(ReviewFindingPayload)

    // MARK: Progress

    case progressUpdate(ProgressPayload)

    // MARK: Diagnostics

    case circuitBreakerTriggered(CircuitBreakerPayload)
    case backpressureChanged(BackpressurePayload)
    case providerHealthChanged(ProviderHealthPayload)
    case errorBudgetLow(ErrorBudgetPayload)
}

// MARK: - Payloads

public struct JobStartedPayload: Sendable {
    public let jobId: String
    public let mode: PipelineMode
    public let taskCount: Int
    public init(jobId: String, mode: PipelineMode, taskCount: Int) {
        self.jobId = jobId; self.mode = mode; self.taskCount = taskCount
    }
}

public struct JobCompletedPayload: Sendable {
    public let jobId: String
    public let durationMs: Int
    public let completedTasks: Int
    public let totalTasks: Int
    public init(jobId: String, durationMs: Int, completedTasks: Int, totalTasks: Int) {
        self.jobId = jobId; self.durationMs = durationMs
        self.completedTasks = completedTasks; self.totalTasks = totalTasks
    }
}

public struct JobFailedPayload: Sendable {
    public let jobId: String
    public let reason: String
    public let failedTasks: Int
    public init(jobId: String, reason: String, failedTasks: Int) {
        self.jobId = jobId; self.reason = reason; self.failedTasks = failedTasks
    }
}

public struct TaskStartedPayload: Sendable {
    public let jobId: String
    public let taskId: String
    public let title: String
    public let agentName: String
    public let role: AgentRole
    public init(jobId: String, taskId: String, title: String, agentName: String, role: AgentRole) {
        self.jobId = jobId; self.taskId = taskId; self.title = title
        self.agentName = agentName; self.role = role
    }
}

public struct TaskCompletedPayload: Sendable {
    public let jobId: String
    public let taskId: String
    public let title: String
    public let agentName: String
    public let role: AgentRole
    public let durationMs: Int
    public init(
        jobId: String, taskId: String, title: String,
        agentName: String, role: AgentRole, durationMs: Int
    ) {
        self.jobId = jobId; self.taskId = taskId; self.title = title
        self.agentName = agentName; self.role = role; self.durationMs = durationMs
    }
}

public struct TaskFailedPayload: Sendable {
    public let jobId: String
    public let taskId: String
    public let error: String
    public init(jobId: String, taskId: String, error: String) {
        self.jobId = jobId; self.taskId = taskId; self.error = error
    }
}

public struct TextDeltaPayload: Sendable {
    public let jobId: String
    public let taskId: String
    public let delta: String
    public init(jobId: String, taskId: String, delta: String) {
        self.jobId = jobId; self.taskId = taskId; self.delta = delta
    }
}

public struct TextReplacePayload: Sendable {
    public let jobId: String
    public let taskId: String
    public let replacement: String
    public init(jobId: String, taskId: String, replacement: String) {
        self.jobId = jobId; self.taskId = taskId; self.replacement = replacement
    }
}

public struct PatchAppliedPayload: Sendable {
    public let jobId: String
    public let taskId: String
    public let touchedFiles: [String]
    public let riskScore: Double
    public init(jobId: String, taskId: String, touchedFiles: [String], riskScore: Double) {
        self.jobId = jobId; self.taskId = taskId
        self.touchedFiles = touchedFiles; self.riskScore = riskScore
    }
}

public struct RollbackPayload: Sendable {
    public let jobId: String
    public let taskId: String
    public let reason: String
    public init(jobId: String, taskId: String, reason: String) {
        self.jobId = jobId; self.taskId = taskId; self.reason = reason
    }
}

public struct ReviewFindingPayload: Sendable {
    public let jobId: String
    public let taskId: String
    public let finding: ReviewFinding
    public init(jobId: String, taskId: String, finding: ReviewFinding) {
        self.jobId = jobId; self.taskId = taskId; self.finding = finding
    }
}

public struct ProgressPayload: Sendable {
    public let jobId: String
    public let completedTasks: Int
    public let totalTasks: Int
    public let currentState: JobState
    public init(jobId: String, completedTasks: Int, totalTasks: Int, currentState: JobState) {
        self.jobId = jobId; self.completedTasks = completedTasks
        self.totalTasks = totalTasks; self.currentState = currentState
    }
}

public struct CircuitBreakerPayload: Sendable {
    public let jobId: String
    public let phase: CircuitBreakerPhase
    public let reason: String
    public init(jobId: String, phase: CircuitBreakerPhase, reason: String) {
        self.jobId = jobId; self.phase = phase; self.reason = reason
    }
}

public struct BackpressurePayload: Sendable {
    public let jobId: String
    public let active: Bool
    public let activeWorkers: Int
    public let maxWorkers: Int
    public init(jobId: String, active: Bool, activeWorkers: Int, maxWorkers: Int) {
        self.jobId = jobId; self.active = active
        self.activeWorkers = activeWorkers; self.maxWorkers = maxWorkers
    }
}

public struct ProviderHealthPayload: Sendable {
    public let jobId: String
    public let providerId: String
    public let status: ProviderHealthStatus
    public init(jobId: String, providerId: String, status: ProviderHealthStatus) {
        self.jobId = jobId; self.providerId = providerId; self.status = status
    }
}

public struct ErrorBudgetPayload: Sendable {
    public let jobId: String
    public let failedPercent: Int
    public let maxPercent: Int
    public let consecutiveFailures: Int
    public init(jobId: String, failedPercent: Int, maxPercent: Int, consecutiveFailures: Int) {
        self.jobId = jobId; self.failedPercent = failedPercent
        self.maxPercent = maxPercent; self.consecutiveFailures = consecutiveFailures
    }
}

public struct RawEventPayload: Sendable {
    public let jobId: String
    public let taskId: String
    public let rawType: String
    public let payload: [String: String]
    public init(
        jobId: String, taskId: String,
        rawType: String, payload: [String: String]
    ) {
        self.jobId = jobId; self.taskId = taskId
        self.rawType = rawType; self.payload = payload
    }
}
