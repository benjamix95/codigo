import Foundation

// MARK: - RollbackRecord

/// Record di un'operazione di rollback (§6.12).
public struct RollbackRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { rollbackId }

    public var rollbackId: String
    public var jobId: String
    public var taskId: String
    public var patchId: String
    public var strategy: RollbackStrategy
    public var rollbackRef: String
    public var filesRestored: [String]
    public var startedAt: Date
    public var completedAt: Date?
    public var status: RollbackStatus
    public var verificationPassed: Bool
    public var checksums: [String: String]

    public init(
        rollbackId: String,
        jobId: String,
        taskId: String,
        patchId: String,
        strategy: RollbackStrategy,
        rollbackRef: String,
        filesRestored: [String],
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        status: RollbackStatus = .inProgress,
        verificationPassed: Bool = false,
        checksums: [String: String] = [:]
    ) {
        self.rollbackId = rollbackId
        self.jobId = jobId
        self.taskId = taskId
        self.patchId = patchId
        self.strategy = strategy
        self.rollbackRef = rollbackRef
        self.filesRestored = filesRestored
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.verificationPassed = verificationPassed
        self.checksums = checksums
    }

    enum CodingKeys: String, CodingKey {
        case rollbackId = "rollback_id"
        case jobId = "job_id"
        case taskId = "task_id"
        case patchId = "patch_id"
        case strategy
        case rollbackRef = "rollback_ref"
        case filesRestored = "files_restored"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case status
        case verificationPassed = "verification_passed"
        case checksums
    }

    /// Durata in ms (nil se non completato).
    public var durationMs: Int? {
        guard let end = completedAt else { return nil }
        return Int(end.timeIntervalSince(startedAt) * 1000)
    }

    /// Rollback deve completare entro 10s (§5.3 inv.4).
    public var isOvertime: Bool {
        guard let ms = durationMs else { return false }
        return ms > 10_000
    }
}

/// Stato dell'operazione di rollback.
public enum RollbackStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case inProgress = "in_progress"
    case success
    case failed
}

extension RollbackRecord: PipelineValidatable {
    public func validate() throws {
        let c = "RollbackRecord"
        try PipelineValidationHelpers.requireNonEmpty(
            rollbackId, field: "rollback_id", contract: c
        )
        try PipelineValidationHelpers.requireNonEmpty(jobId, field: "job_id", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(taskId, field: "task_id", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(patchId, field: "patch_id", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(
            rollbackRef, field: "rollback_ref", contract: c
        )
        try PipelineValidationHelpers.requireNonEmptyArray(
            filesRestored, field: "files_restored", contract: c
        )
    }
}
