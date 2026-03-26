import Foundation
import os

/// Punti di interesse per Instruments (SwiftUI / Time Profiler) sul percorso Rust → Swift dello stream principale.
/// Categoria: **RuntimeStream** (subsystem `com.solocode.app`). Profilare una build **Debug** per vedere gli span.
enum RuntimeStreamSignpost {
    private static let log = OSLog(subsystem: "com.solocode.app", category: "RuntimeStream")

    static func measurePoll<T>(timeoutMs: Int, _ work: () -> T) -> T {
        #if DEBUG
        let sid = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "RuntimePoll", signpostID: sid, "%{public}d", timeoutMs)
        defer { os_signpost(.end, log: log, name: "RuntimePoll", signpostID: sid) }
        return work()
        #else
        return work()
        #endif
    }

    static func measureMainActorTextFlush(_ work: () -> Void) {
        #if DEBUG
        let sid = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "RuntimeStreamTextFlush", signpostID: sid)
        defer { os_signpost(.end, log: log, name: "RuntimeStreamTextFlush", signpostID: sid) }
        work()
        #else
        work()
        #endif
    }
}
