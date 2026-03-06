import Foundation

extension EventNormalizer {
    static func normalizeDebugNativeSession(
        payload: [String: String],
        timestamp: Date
    ) -> [NormalizedEvent] {
        var events: [NormalizedEvent] = []
        if let nativePayload = parseDebugNativeSessionPayload(payload: payload) {
            events.append(.debugNativeSession(nativePayload))
        }

        let action = payload["action"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "native"
        let detail = payload["detail"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? payload["last_error"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        events.append(.taskActivity(TaskActivity(
            type: "debug_native_session",
            title: payload["title"] ?? "Native debug • \(action)",
            detail: detail,
            payload: payload,
            timestamp: timestamp,
            phase: .executing,
            isRunning: runningStateForType("debug_native_session", payload: payload),
            groupId: debugGroupingId(payload: payload)
        )))
        return events
    }
}
