import Foundation

extension CodebaseIndex {
    func queueRealtimeChange(kind: RealtimeChangeKind, absolutePath: String, relativePath: String) {
        realtimeQueueSequence &+= 1
        let sequence = realtimeQueueSequence
        let previousEnqueueTime = queuedRealtimeChanges[relativePath]?.enqueuedAt
        queuedRealtimeChanges[relativePath] = RealtimeQueuedChange(
            absolutePath: absolutePath,
            relativePath: relativePath,
            kind: kind,
            enqueuedAt: previousEnqueueTime ?? .now,
            sequence: sequence
        )
    }

    func flushQueuedRealtimeChanges() async {
        guard !queuedRealtimeChanges.isEmpty else { return }
        let flushStartedAt = Date()
        let pending = queuedRealtimeChanges.values.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            return lhs.relativePath < rhs.relativePath
        }
        queuedRealtimeChanges.removeAll(keepingCapacity: true)
        let oldestQueuedAt = pending.map(\.enqueuedAt).min() ?? flushStartedAt

        for change in pending {
            switch change.kind {
            case .upsert:
                if FileManager.default.fileExists(atPath: change.absolutePath) {
                    await applyRealtimeFileUpsert(
                        absolutePath: change.absolutePath,
                        canonicalRelativePath: change.relativePath
                    )
                } else {
                    await applyRealtimeFileRemoval(
                        absolutePath: change.absolutePath,
                        canonicalRelativePath: change.relativePath
                    )
                }
            case .remove:
                await applyRealtimeFileRemoval(
                    absolutePath: change.absolutePath,
                    canonicalRelativePath: change.relativePath
                )
            }
        }

        let durationMs = Int(Date().timeIntervalSince(flushStartedAt) * 1000)
        let queueAgeMs = Int(flushStartedAt.timeIntervalSince(oldestQueuedAt) * 1000)
        Self.logger.debug(
            "realtime_queue_flush: batch=\(pending.count, privacy: .public) duration_ms=\(durationMs, privacy: .public) queued_age_ms=\(queueAgeMs, privacy: .public)"
        )
    }
}
