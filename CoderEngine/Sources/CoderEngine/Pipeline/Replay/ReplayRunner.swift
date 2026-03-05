import Foundation

// MARK: - ReplayRunnerError

public enum ReplayRunnerError: Error, Sendable, Equatable {
    case invalidSnapshot(reason: String)
    case eventLogEmpty
    case divergenceDetected(details: String)
}

// MARK: - ReplayDecision

/// Singola decisione orchestrator estratta dal log (§6.10).
public struct ReplayDecision: Sendable, Equatable {
    public let sequenceNumber: UInt64
    public let event: String
    public let phase: String
    public let jobId: String
    public let taskId: String?
    public let metadata: [String: String]

    public init(
        sequenceNumber: UInt64,
        event: String,
        phase: String,
        jobId: String,
        taskId: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.sequenceNumber = sequenceNumber
        self.event = event
        self.phase = phase
        self.jobId = jobId
        self.taskId = taskId
        self.metadata = metadata
    }
}

// MARK: - ReplayDivergence

/// Report di divergenza tra run originale e replay (§6.10).
public struct ReplayDivergence: Sendable, Equatable {
    public let sequenceNumber: UInt64
    public let expected: ReplayDecision
    public let actual: ReplayDecision?
    public let reason: String

    public init(
        sequenceNumber: UInt64,
        expected: ReplayDecision,
        actual: ReplayDecision?,
        reason: String
    ) {
        self.sequenceNumber = sequenceNumber
        self.expected = expected
        self.actual = actual
        self.reason = reason
    }
}

// MARK: - ReplayReport

/// Report finale del replay (§6.10, §23.6).
public struct ReplayReport: Sendable, Equatable {
    public let snapshot: ReplaySnapshot
    public let totalDecisions: Int
    public let matchedDecisions: Int
    public let divergences: [ReplayDivergence]
    public let replayDurationMs: Int

    public var matchRate: Double {
        guard totalDecisions > 0 else { return 0 }
        return Double(matchedDecisions) / Double(totalDecisions)
    }

    public var isFullMatch: Bool {
        divergences.isEmpty
    }

    public init(
        snapshot: ReplaySnapshot,
        totalDecisions: Int,
        matchedDecisions: Int,
        divergences: [ReplayDivergence],
        replayDurationMs: Int
    ) {
        self.snapshot = snapshot
        self.totalDecisions = totalDecisions
        self.matchedDecisions = matchedDecisions
        self.divergences = divergences
        self.replayDurationMs = replayDurationMs
    }
}

// MARK: - ReplayRunner

/// Runner per replay deterministico della pipeline (§6.10, §23.6).
///
/// Responsabilità:
/// 1. Carica `replay_snapshot.json`
/// 2. Replay deterministico su log eventi e provider selection
/// 3. Genera report diff tra run originale e replay
///
/// Nota: divergenze output LLM sono attese e non sono failure (§6.10).
public struct ReplayRunner: Sendable {

    /// Tipi di evento che rappresentano decisioni orchestrator.
    static let orchestratorDecisionEvents: Set<String> = [
        "task_started", "task_completed", "task_failed",
        "lock_acquired", "lock_released",
        "rollback_started", "rollback_completed",
        "circuit_breaker_triggered",
        "scheduler_backpressure",
        "job_timeout", "error_budget_low",
    ]

    public init() {}

    // MARK: - Parse Event Log

    /// Estrae le decisioni orchestrator da un array di EventLogEntry.
    public func extractDecisions(
        from entries: [EventLogEntry]
    ) -> [ReplayDecision] {
        entries
            .filter {
                Self.orchestratorDecisionEvents.contains($0.event)
            }
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
            .map { entry in
                ReplayDecision(
                    sequenceNumber: entry.sequenceNumber,
                    event: entry.event,
                    phase: entry.phase,
                    jobId: entry.jobId,
                    taskId: entry.taskId,
                    metadata: entry.metadata ?? [:]
                )
            }
    }

    // MARK: - Compare Runs

    /// Confronta due sequenze di decisioni e produce le divergenze.
    public func compare(
        original: [ReplayDecision],
        replay: [ReplayDecision]
    ) -> [ReplayDivergence] {
        var divergences: [ReplayDivergence] = []
        let maxCount = max(original.count, replay.count)

        for i in 0..<maxCount {
            let orig = i < original.count ? original[i] : nil
            let rep = i < replay.count ? replay[i] : nil

            if let o = orig, let r = rep {
                if o.event != r.event || o.phase != r.phase
                    || o.taskId != r.taskId
                {
                    divergences.append(ReplayDivergence(
                        sequenceNumber: o.sequenceNumber,
                        expected: o,
                        actual: r,
                        reason: divergenceReason(expected: o, actual: r)
                    ))
                }
            } else if let o = orig {
                divergences.append(ReplayDivergence(
                    sequenceNumber: o.sequenceNumber,
                    expected: o,
                    actual: nil,
                    reason: "Decision missing in replay"
                ))
            } else if let r = rep {
                divergences.append(ReplayDivergence(
                    sequenceNumber: r.sequenceNumber,
                    expected: r,
                    actual: nil,
                    reason: "Extra decision in replay"
                ))
            }
        }
        return divergences
    }

    // MARK: - Replay

    /// Esegue il replay completo confrontando le decisioni originali
    /// con quelle del replay.
    public func replay(
        snapshot: ReplaySnapshot,
        originalEntries: [EventLogEntry],
        replayEntries: [EventLogEntry]
    ) throws -> ReplayReport {
        try snapshot.validate()

        let originalDecisions = extractDecisions(from: originalEntries)
        guard !originalDecisions.isEmpty else {
            throw ReplayRunnerError.eventLogEmpty
        }

        let replayDecisions = extractDecisions(from: replayEntries)
        let divergences = compare(
            original: originalDecisions,
            replay: replayDecisions
        )

        let matched = originalDecisions.count - divergences.count
        return ReplayReport(
            snapshot: snapshot,
            totalDecisions: originalDecisions.count,
            matchedDecisions: max(matched, 0),
            divergences: divergences,
            replayDurationMs: 0
        )
    }

    // MARK: - Private

    private func divergenceReason(
        expected: ReplayDecision,
        actual: ReplayDecision
    ) -> String {
        var parts: [String] = []
        if expected.event != actual.event {
            parts.append(
                "event: \(expected.event) → \(actual.event)"
            )
        }
        if expected.phase != actual.phase {
            parts.append(
                "phase: \(expected.phase) → \(actual.phase)"
            )
        }
        if expected.taskId != actual.taskId {
            parts.append(
                "taskId: \(expected.taskId ?? "nil")"
                + " → \(actual.taskId ?? "nil")"
            )
        }
        return parts.joined(separator: "; ")
    }
}
