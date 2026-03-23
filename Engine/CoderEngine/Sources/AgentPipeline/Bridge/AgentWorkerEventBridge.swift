import Foundation

// MARK: - AgentWorkerEventBridge

/// Bridges `AgentWorkerDelegate` streaming events to the pipeline `EventBus`.
/// Converts textDelta, textReplace and raw events from the worker adapter
/// into `EventBusEvent` instances that the UI bridge can map to `PipelineUIEvent`.
public final class AgentWorkerEventBridge: AgentWorkerDelegate, @unchecked Sendable {

    private actor SequenceGenerator {
        private var nextValue: UInt64 = 0

        func next() -> UInt64 {
            nextValue += 1
            return nextValue
        }
    }

    private let eventBus: EventBus
    private let jobId: String
    private let sequencer = SequenceGenerator()

    public init(eventBus: EventBus, jobId: String) {
        self.eventBus = eventBus
        self.jobId = jobId
    }

    // MARK: - AgentWorkerDelegate

    public func worker(
        jobId: String, taskId: String,
        didEmitTextDelta delta: String
    ) async {
        let seq = await sequencer.next()
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
        let seq = await sequencer.next()
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
        let seq = await sequencer.next()
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

}
