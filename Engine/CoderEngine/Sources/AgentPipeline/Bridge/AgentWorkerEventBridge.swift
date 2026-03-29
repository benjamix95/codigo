import Foundation
import os

// MARK: - AgentWorkerEventBridge

/// Bridges `AgentWorkerDelegate` streaming events to the pipeline `EventBus`.
/// Converts textDelta, textReplace and raw events from the worker adapter
/// into `EventBusEvent` instances that the UI bridge can map to `PipelineUIEvent`.
public final class AgentWorkerEventBridge: AgentWorkerDelegate, @unchecked Sendable {

    /// Lock-free sequence generator — eliminates actor hop overhead in hot-path.
    /// Previous `actor SequenceGenerator` required an async context switch on every
    /// event (20-50/sec during streaming). `OSAllocatedUnfairLock` is synchronous
    /// and ~100x faster for this use case.
    private let sequencer = OSAllocatedUnfairLock(initialState: UInt64(0))

    private func nextSequence() -> UInt64 {
        sequencer.withLock { value in
            value += 1
            return value
        }
    }

    private func identifiers(
        sequence: UInt64,
        kind: String,
        taskId: String
    ) -> (eventId: String, idempotencyKey: String) {
        let sequenceString = String(sequence)
        return (
            eventId: "evt_stream_" + sequenceString + "_" + kind + "_" + taskId,
            idempotencyKey: jobId + "_" + kind + "_" + sequenceString + "_" + taskId
        )
    }

    private let eventBus: EventBus
    private let jobId: String
    /// Protected by lock — accessed from multiple threads (shutdown() + publishOrLog).
    private let isShutdownLock = OSAllocatedUnfairLock(initialState: false)

    public init(eventBus: EventBus, jobId: String) {
        self.eventBus = eventBus
        self.jobId = jobId
    }

    // MARK: - Lifecycle

    /// Arresta il bridge: tutte le publish successive vengono ignorate.
    public func shutdown() {
        isShutdownLock.withLock { $0 = true }
    }

    // MARK: - Private Helpers

    private func publishOrLog(_ event: EventBusEvent, taskId: String) async {
        guard !isShutdownLock.withLock({ $0 }) else {
            NSLog("[AgentWorkerEventBridge] publish skipped (bridge shutdown), eventType=%@, taskId=%@", "\(event.type)", taskId)
            return
        }
        do {
            try await eventBus.publish(event)
        } catch let error as EventBusError {
            switch error {
            case .duplicateIdempotencyKey:
                break
            case .busShutdown:
                NSLog("[AgentWorkerEventBridge] publish skipped (bus shutdown), eventType=%@, taskId=%@", "\(event.type)", taskId)
            case .invalidEvent(let reason):
                NSLog("[AgentWorkerEventBridge] publish failed (invalid event): %@, eventType=%@, taskId=%@", reason, "\(event.type)", taskId)
            }
        } catch {
            NSLog("[AgentWorkerEventBridge] publish failed: %@, eventType=%@, taskId=%@", "\(error)", "\(event.type)", taskId)
        }
    }

    // MARK: - AgentWorkerDelegate

    public func worker(
        jobId: String, taskId: String,
        didEmitTextDelta delta: String
    ) async {
        let seq = nextSequence()
        let ids = identifiers(sequence: seq, kind: "delta", taskId: taskId)
        let event = EventBusEvent(
            eventId: ids.eventId,
            jobId: self.jobId,
            taskId: taskId,
            type: .textDelta,
            payload: ["delta": delta, "task_id": taskId],
            sequenceNumber: seq,
            idempotencyKey: ids.idempotencyKey
        )
        await publishOrLog(event, taskId: taskId)
    }

    public func worker(
        jobId: String, taskId: String,
        didReplace replacement: String
    ) async {
        let seq = nextSequence()
        let ids = identifiers(sequence: seq, kind: "replace", taskId: taskId)
        let event = EventBusEvent(
            eventId: ids.eventId,
            jobId: self.jobId,
            taskId: taskId,
            type: .textReplace,
            payload: ["replacement": replacement, "task_id": taskId],
            sequenceNumber: seq,
            idempotencyKey: ids.idempotencyKey
        )
        await publishOrLog(event, taskId: taskId)
    }

    public func worker(
        jobId: String, taskId: String,
        didEmitRaw type: String, payload: [String: String]
    ) async {
        let seq = nextSequence()
        let ids = identifiers(sequence: seq, kind: "raw", taskId: taskId)
        var mergedPayload = payload
        mergedPayload["raw_type"] = type
        mergedPayload["task_id"] = taskId

        let event = EventBusEvent(
            eventId: ids.eventId,
            jobId: self.jobId,
            taskId: taskId,
            type: .rawAgentEvent,
            payload: mergedPayload,
            sequenceNumber: seq,
            idempotencyKey: ids.idempotencyKey
        )
        await publishOrLog(event, taskId: taskId)
    }

}
