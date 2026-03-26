import Foundation
import os

/// Segnala in Instruments (Points of Interest) il tempo trascorso sul main actor in `consumePipelineEvents`.
enum PipelineIntegrationConsumeEventsSignpost {
    private static let log = OSLog(subsystem: "com.solocode.app", category: "PipelineMainActor")

    static func measure<T>(eventCount: Int, _ work: () throws -> T) rethrows -> T {
        #if DEBUG
        let signpostID = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: "ConsumePipelineEvents",
            signpostID: signpostID,
            "%{public}d",
            eventCount
        )
        defer {
            os_signpost(.end, log: log, name: "ConsumePipelineEvents", signpostID: signpostID)
        }
        return try work()
        #else
        return try work()
        #endif
    }
}
