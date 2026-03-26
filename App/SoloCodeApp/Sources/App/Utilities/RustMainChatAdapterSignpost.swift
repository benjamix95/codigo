import Foundation
import os

/// Points of Interest per Instruments: round-trip `applyUIIntent` (FFI + apply su ChatStore).
enum RustMainChatAdapterSignpost {
    private static let log = OSLog(subsystem: "com.solocode.app", category: "RustMainChat")

    @MainActor
    static func measureApplyUIIntent(
        intentLabel: String,
        _ work: () -> MainChatUIIntentResponseBridge?
    ) -> MainChatUIIntentResponseBridge? {
        #if DEBUG
        let signpostID = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: "RustApplyUIIntent",
            signpostID: signpostID,
            "%{public}s",
            intentLabel
        )
        defer {
            os_signpost(.end, log: log, name: "RustApplyUIIntent", signpostID: signpostID)
        }
        return work()
        #else
        return work()
        #endif
    }
}
