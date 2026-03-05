import Foundation

// MARK: - ProviderSelection

/// Record di selezione provider per fase, usato nel replay (§6.10).
public struct ProviderSelection: Codable, Sendable, Equatable {
    public var phase: String
    public var provider: String

    public init(phase: String, provider: String) {
        self.phase = phase
        self.provider = provider
    }
}

// MARK: - ReplaySnapshot

/// Contratto dati per il replay deterministico della pipeline (§6.10).
/// Il replay riproduce decisioni orchestrator, NON output LLM.
public struct ReplaySnapshot: Codable, Sendable, Equatable {
    public var jobSnapshotPath: String
    public var eventLogPath: String
    public var providerSelection: [ProviderSelection]
    public var seed: String
    public var replayScope: ReplayScope

    public init(
        jobSnapshotPath: String,
        eventLogPath: String,
        providerSelection: [ProviderSelection] = [],
        seed: String = "",
        replayScope: ReplayScope = .orchestratorDecisions
    ) {
        self.jobSnapshotPath = jobSnapshotPath
        self.eventLogPath = eventLogPath
        self.providerSelection = providerSelection
        self.seed = seed
        self.replayScope = replayScope
    }

    enum CodingKeys: String, CodingKey {
        case jobSnapshotPath = "job_snapshot_path"
        case eventLogPath = "event_log_path"
        case providerSelection = "provider_selection"
        case seed
        case replayScope = "replay_scope"
    }
}

/// Scope del replay (§6.10).
public enum ReplayScope: String, Codable, Sendable, Equatable, CaseIterable {
    case orchestratorDecisions = "orchestrator_decisions"
}

extension ReplaySnapshot: PipelineValidatable {
    public func validate() throws {
        let c = "ReplaySnapshot"
        try PipelineValidationHelpers.requireNonEmpty(
            jobSnapshotPath, field: "job_snapshot_path", contract: c
        )
        try PipelineValidationHelpers.requireNonEmpty(
            eventLogPath, field: "event_log_path", contract: c
        )
    }
}
