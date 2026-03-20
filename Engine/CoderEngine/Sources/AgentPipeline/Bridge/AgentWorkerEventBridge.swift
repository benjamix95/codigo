import Foundation

// MARK: - AgentWorkerEventBridge

/// Bridges `AgentWorkerDelegate` streaming events to the pipeline `EventBus`.
/// Converts textDelta, textReplace and raw events from the worker adapter
/// into `EventBusEvent` instances that the UI bridge can map to `PipelineUIEvent`.
public final class AgentWorkerEventBridge: AgentWorkerDelegate, @unchecked Sendable {

    private let eventBus: EventBus
    private let jobId: String
    private var sequence: UInt64 = 0

    public init(eventBus: EventBus, jobId: String) {
        self.eventBus = eventBus
        self.jobId = jobId
    }

    // MARK: - AgentWorkerDelegate

    public func worker(
        jobId: String, taskId: String,
        didEmitTextDelta delta: String
    ) async {
        let seq = nextSequence()
        let event = EventBusEvent(
            eventId: "evt_stream_\(seq)_delta_\(taskId)",
            jobId: self.jobId,
            taskId: taskId,
            type: .textDelta,
            payload: ["delta": delta, "task_id": taskId],
            sequenceNumber: seq,
            idempotencyKey: "\(self.jobId)_delta_\(seq)_\(taskId)"
        )
        try? await eventBus.publish(event)
    }

    public func worker(
        jobId: String, taskId: String,
        didReplace replacement: String
    ) async {
        let seq = nextSequence()
        let event = EventBusEvent(
            eventId: "evt_stream_\(seq)_replace_\(taskId)",
            jobId: self.jobId,
            taskId: taskId,
            type: .textReplace,
            payload: ["replacement": replacement, "task_id": taskId],
            sequenceNumber: seq,
            idempotencyKey: "\(self.jobId)_replace_\(seq)_\(taskId)"
        )
        try? await eventBus.publish(event)
    }

    public func worker(
        jobId: String, taskId: String,
        didEmitRaw type: String, payload: [String: String]
    ) async {
        let seq = nextSequence()
        var mergedPayload = payload
        mergedPayload["raw_type"] = type
        mergedPayload["task_id"] = taskId

        let event = EventBusEvent(
            eventId: "evt_stream_\(seq)_raw_\(taskId)",
            jobId: self.jobId,
            taskId: taskId,
            type: .rawAgentEvent,
            payload: mergedPayload,
            sequenceNumber: seq,
            idempotencyKey: "\(self.jobId)_raw_\(seq)_\(taskId)"
        )
        try? await eventBus.publish(event)
    }

    // MARK: - Private

    private func nextSequence() -> UInt64 {
        sequence += 1
        return sequence
    }
}
