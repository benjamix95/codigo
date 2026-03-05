import Foundation

// MARK: - EventBusEvent

/// Evento nel bus interno della pipeline (§6.9).
/// At-least-once delivery con idempotency key.
public struct EventBusEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String { eventId }

    public var eventId: String
    public var jobId: String
    public var taskId: String?
    public var agentId: String?
    public var correlationId: String?
    public var type: PipelineEventType
    public var payload: [String: String]
    public var timestamp: Date
    public var sequenceNumber: UInt64
    public var idempotencyKey: String
    public var deliveryStatus: DeliveryStatus
    public var deliveryAttempts: Int

    public init(
        eventId: String,
        jobId: String,
        taskId: String? = nil,
        agentId: String? = nil,
        correlationId: String? = nil,
        type: PipelineEventType,
        payload: [String: String] = [:],
        timestamp: Date = Date(),
        sequenceNumber: UInt64 = 0,
        idempotencyKey: String,
        deliveryStatus: DeliveryStatus = .pending,
        deliveryAttempts: Int = 0
    ) {
        self.eventId = eventId
        self.jobId = jobId
        self.taskId = taskId
        self.agentId = agentId
        self.correlationId = correlationId
        self.type = type
        self.payload = payload
        self.timestamp = timestamp
        self.sequenceNumber = sequenceNumber
        self.idempotencyKey = idempotencyKey
        self.deliveryStatus = deliveryStatus
        self.deliveryAttempts = deliveryAttempts
    }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case jobId = "job_id"
        case taskId = "task_id"
        case agentId = "agent_id"
        case correlationId = "correlation_id"
        case type
        case payload
        case timestamp
        case sequenceNumber = "sequence_number"
        case idempotencyKey = "idempotency_key"
        case deliveryStatus = "delivery_status"
        case deliveryAttempts = "delivery_attempts"
    }

    /// Deve andare in DLQ dopo 3 tentativi falliti (§6.9).
    public var shouldDeadLetter: Bool {
        deliveryAttempts >= 3 && deliveryStatus == .failed
    }
}

extension EventBusEvent: PipelineValidatable {
    public func validate() throws {
        let c = "EventBusEvent"
        try PipelineValidationHelpers.requireNonEmpty(eventId, field: "event_id", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(jobId, field: "job_id", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(
            idempotencyKey, field: "idempotency_key", contract: c
        )
    }
}
