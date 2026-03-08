import Foundation

// MARK: - EventLogEntry

/// Singola entry nell'event log append-only (§6.7).
/// Formato NDJSON — ogni riga è un EventLogEntry serializzato.
public struct EventLogEntry: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var jobId: String
    public var taskId: String?
    public var agentId: String?
    public var agentName: String?
    public var correlationId: String?
    public var phase: String
    public var event: String
    public var sequenceNumber: UInt64
    public var metadata: [String: String]?

    public init(
        timestamp: Date = Date(),
        jobId: String,
        taskId: String? = nil,
        agentId: String? = nil,
        agentName: String? = nil,
        correlationId: String? = nil,
        phase: String,
        event: String,
        sequenceNumber: UInt64,
        metadata: [String: String]? = nil
    ) {
        self.timestamp = timestamp
        self.jobId = jobId
        self.taskId = taskId
        self.agentId = agentId
        self.agentName = agentName
        self.correlationId = correlationId
        self.phase = phase
        self.event = event
        self.sequenceNumber = sequenceNumber
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case timestamp = "ts"
        case jobId = "job_id"
        case taskId = "task_id"
        case agentId = "agent_id"
        case agentName = "agent_name"
        case correlationId = "correlation_id"
        case phase
        case event
        case sequenceNumber = "sequence_number"
        case metadata
    }
}

extension EventLogEntry: PipelineValidatable {
    public func validate() throws {
        let c = "EventLogEntry"
        try PipelineValidationHelpers.requireNonEmpty(jobId, field: "job_id", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(phase, field: "phase", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(event, field: "event", contract: c)
    }
}
