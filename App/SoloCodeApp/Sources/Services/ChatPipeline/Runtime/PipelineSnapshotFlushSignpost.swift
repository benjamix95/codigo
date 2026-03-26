import Foundation
import os

/// Points of Interest: batch aggiornamento `snapshotsByConversation` sul main actor.
enum PipelineSnapshotFlushSignpost {
    private static let log = OSLog(subsystem: "com.solocode.app", category: "PipelineSnapshot")

    @MainActor
    static func measureBatch(dirtyCount: Int, _ work: () -> Void) {
        #if DEBUG
        let signpostID = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: "FlushPipelineSnapshots",
            signpostID: signpostID,
            "%{public}d",
            dirtyCount
        )
        defer {
            os_signpost(.end, log: log, name: "FlushPipelineSnapshots", signpostID: signpostID)
        }
        work()
        #else
        work()
        #endif
    }
}
