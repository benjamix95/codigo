import Foundation

extension CodebaseIndex {
    func queueRealtimeChange(kind: RealtimeChangeKind, absolutePath: String, relativePath: String) {
        queuedRealtimeChanges[relativePath] = RealtimeQueuedChange(
            absolutePath: absolutePath,
            relativePath: relativePath,
            kind: kind
        )
    }

    func flushQueuedRealtimeChanges() async {
        guard !queuedRealtimeChanges.isEmpty else { return }
        let pending = queuedRealtimeChanges.values.sorted { $0.relativePath < $1.relativePath }
        queuedRealtimeChanges.removeAll(keepingCapacity: true)

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
    }
}
