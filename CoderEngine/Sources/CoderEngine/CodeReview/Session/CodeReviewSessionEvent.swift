import Foundation

// MARK: - CodeReviewSessionEvent

/// Structured event emitted during a code review session.
public struct CodeReviewSessionEvent: Sendable, Identifiable, Codable {
    public let id: String
    public let type: EventType
    public let timestamp: Date
    public let detail: String?
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        type: EventType,
        timestamp: Date = Date(),
        detail: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.detail = detail
        self.metadata = metadata
    }
}

// MARK: - EventType

extension CodeReviewSessionEvent {
    public enum EventType: String, Sendable, Codable, CaseIterable {
        case sessionStarted = "session_started"
        case analysisStarted = "analysis_started"
        case analysisCompleted = "analysis_completed"
        case auditStarted = "audit_started"
        case auditCompleted = "audit_completed"
        case candidateAdded = "candidate_added"
        case candidateVerified = "candidate_verified"
        case candidateRejected = "candidate_rejected"
        case findingAdded = "finding_added"
        case findingFixApplied = "finding_fix_applied"
        case findingDismissed = "finding_dismissed"
        case findingCommented = "finding_commented"
        case patchPrepared = "patch_prepared"
        case patchVerified = "patch_verified"
        case patchApplyFailed = "patch_apply_failed"
        case prOpened = "pr_opened"
        case prMerged = "pr_merged"
        case conflictDetected = "conflict_detected"
        case outcomePublished = "outcome_published"
        case roundStarted = "round_started"
        case roundCompleted = "round_completed"
        case workerSpawned = "worker_spawned"
        case workerCompleted = "worker_completed"
        case testsPassed = "tests_passed"
        case testsFailed = "tests_failed"
        case configUpdated = "config_updated"
        case sessionCompleted = "session_completed"
        case error = "error"
    }
}

// MARK: - Convenience Factories

extension CodeReviewSessionEvent {
    public static func sessionStarted(
        scope: String,
        fileCount: Int
    ) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .sessionStarted,
            detail: "Review started with scope: \(scope)",
            metadata: [
                "scope": scope,
                "file_count": String(fileCount),
            ]
        )
    }

    public static func findingAdded(
        findingId: String,
        severity: String,
        filePath: String
    ) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .findingAdded,
            detail: "[\(severity)] \(filePath)",
            metadata: [
                "finding_id": findingId,
                "severity": severity,
                "file_path": filePath,
            ]
        )
    }

    public static func candidateAdded(
        candidateId: String,
        filePath: String
    ) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .candidateAdded,
            detail: filePath,
            metadata: ["candidate_id": candidateId, "file_path": filePath]
        )
    }

    public static func candidateVerified(candidateId: String) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .candidateVerified,
            detail: "Candidate \(candidateId) verified",
            metadata: ["candidate_id": candidateId]
        )
    }

    public static func candidateRejected(
        candidateId: String,
        reason: String
    ) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .candidateRejected,
            detail: "Candidate \(candidateId) rejected",
            metadata: ["candidate_id": candidateId, "reason": reason]
        )
    }

    public static func findingFixApplied(findingId: String) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .findingFixApplied,
            detail: "Fix applied for finding \(findingId)",
            metadata: ["finding_id": findingId]
        )
    }

    public static func findingDismissed(
        findingId: String,
        reason: String
    ) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .findingDismissed,
            detail: "Finding \(findingId) dismissed: \(reason)",
            metadata: [
                "finding_id": findingId,
                "reason": reason,
            ]
        )
    }

    public static func roundStarted(round: Int, maxRounds: Int) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .roundStarted,
            detail: "Round \(round)/\(maxRounds)",
            metadata: [
                "round": String(round),
                "max_rounds": String(maxRounds),
            ]
        )
    }

    public static func error(_ message: String) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .error,
            detail: message
        )
    }

    public static func patchPrepared(
        patchId: String,
        findingId: String
    ) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .patchPrepared,
            detail: "Patch prepared for finding \(findingId)",
            metadata: ["patch_id": patchId, "finding_id": findingId]
        )
    }
}

// MARK: - Payload Serialization

extension CodeReviewSessionEvent {
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    public func toPayload() -> [String: String] {
        var payload: [String: String] = [
            "id": id,
            "type": type.rawValue,
            "timestamp": Self.iso8601Formatter.string(from: timestamp),
        ]
        if let detail { payload["detail"] = detail }
        for (key, value) in metadata {
            payload["meta_\(key)"] = value
        }
        return payload
    }
}
