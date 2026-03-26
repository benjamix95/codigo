import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    /// Eventi stream del review “full panel”: aggiorna attività/todo senza transcript né FFI per delta testuali.
    func handlePanelReviewStreamEvent(_ event: StreamEvent) {
        switch event {
        case .raw(let type, let payload):
            ingestRawReviewActivity(type: type, payload: payload)
            syncTodoIfNeeded(type: type, payload: payload)
        case .error(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                appendPanelSystemMessage(trimmed, kind: .statusNote)
            }
        default:
            break
        }
    }

    func flushReviewPanelStreamDeltas(
        activityId: UUID,
        runtime: ReviewPanelActionOutputRuntime
    ) {
        reviewPanelStreamDeltaCoalesceTasks[activityId]?.cancel()
        reviewPanelStreamDeltaCoalesceTasks[activityId] = nil
        let merged = reviewPanelStreamDeltaCoalesceBuffers.removeValue(forKey: activityId) ?? ""
        guard !merged.isEmpty else { return }
        applyReviewPanelStreamReduce(id: activityId, event: .textDelta(merged), runtime: runtime)
    }

    func resetReviewPanelStreamCoalescer(for activityId: UUID) {
        reviewPanelStreamDeltaCoalesceTasks[activityId]?.cancel()
        reviewPanelStreamDeltaCoalesceTasks[activityId] = nil
        reviewPanelStreamDeltaCoalesceBuffers.removeValue(forKey: activityId)
    }

    func coalesceReviewPanelTextDelta(
        activityId: UUID,
        runtime: ReviewPanelActionOutputRuntime,
        delta: String
    ) {
        if delta.isEmpty { return }
        reviewPanelStreamDeltaCoalesceBuffers[activityId, default: ""] += delta

        if (reviewPanelStreamDeltaCoalesceBuffers[activityId]?.count ?? 0) >= Self.reviewPanelStreamDeltaCoalesceMaxChars {
            flushReviewPanelStreamDeltas(activityId: activityId, runtime: runtime)
            return
        }

        reviewPanelStreamDeltaCoalesceTasks[activityId]?.cancel()
        reviewPanelStreamDeltaCoalesceTasks[activityId] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.reviewPanelStreamDeltaCoalesceNanos)
            } catch {
                return
            }
            guard let self else { return }
            guard !Task.isCancelled else { return }
            self.flushReviewPanelStreamDeltas(activityId: activityId, runtime: runtime)
        }
    }

    private static let reviewPanelStreamDeltaCoalesceNanos: UInt64 = 80_000_000
    private static let reviewPanelStreamDeltaCoalesceMaxChars = 65_536
}
