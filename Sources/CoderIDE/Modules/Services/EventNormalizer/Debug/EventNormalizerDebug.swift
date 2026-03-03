import Foundation

extension EventNormalizer {
    static func normalizeDebugPhaseUpdate(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        let phaseValue = payload["phase"]
        let phase = debugFlowPhase(from: phaseValue) ?? .describing
        let detail = payload["detail"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            .debugPhaseUpdate(phase: phase, detail: detail),
            .taskActivity(TaskActivity(
                type: "debug_phase_update",
                title: "Debug phase • \(phase.label)",
                detail: detail,
                payload: payload,
                timestamp: timestamp,
                phase: .executing,
                isRunning: false,
                groupId: payload["group_id"] ?? "debug_phase_update"
            ))
        ]
    }

    static func normalizeDebugUserRequest(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        let kind = (payload["kind"] ?? "question")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let prompt = (
            payload["prompt"]
                ?? payload["detail"]
                ?? payload["message"]
                ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return [] }

        return [
            .debugUserRequest(kind: kind, prompt: prompt),
            .taskActivity(TaskActivity(
                type: "debug_user_request",
                title: kind == "reproduce" ? "Debug request • reproduce" : "Debug request • question",
                detail: prompt,
                payload: payload,
                timestamp: timestamp,
                phase: .executing,
                isRunning: false
            ))
        ]
    }

    static func normalizeDebugResolved(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        let summary = (
            payload["summary"]
                ?? payload["detail"]
                ?? payload["message"]
                ?? "Debug session resolved"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSummary = summary.isEmpty ? "Debug session resolved" : summary

        return [
            .debugResolved(summary: normalizedSummary),
            .taskActivity(TaskActivity(
                type: "debug_resolved",
                title: "Debug resolved",
                detail: normalizedSummary,
                payload: payload,
                timestamp: timestamp,
                phase: .executing,
                isRunning: false
            ))
        ]
    }

    static func normalizeLegacyDebugPanel(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        let detail = payload["detail"] ?? "Use debug_set_phase, debug_request_user, debug_resolve"
        return [
            .taskActivity(TaskActivity(
                type: "tool_validation_error",
                title: "Legacy debug_panel is not supported",
                detail: detail,
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: false
            ))
        ]
    }

    static func normalizeDebugLog(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        var events: [NormalizedEvent] = []
        if let debugLogPayload = parseDebugLogPayload(payload: payload) {
            events.append(.debugLog(debugLogPayload))
        }
        events.append(.taskActivity(TaskActivity(
            type: "debug_log",
            title: payload["title"] ?? defaultTitle(for: "debug_log"),
            detail: payload["message"] ?? payload["detail"],
            payload: payload,
            timestamp: timestamp,
            phase: phaseForType("debug_log", payload: payload),
            isRunning: runningStateForType("debug_log", payload: payload),
            groupId: payload["group_id"] ?? payload["tool_call_id"]
        )))
        return events
    }

    static func normalizeDebugHypothesize(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        var events: [NormalizedEvent] = []
        if let hypothesisPayload = parseDebugHypothesizePayload(payload: payload) {
            events.append(.debugHypothesize(hypothesisPayload))
        }
        events.append(.taskActivity(TaskActivity(
            type: "debug_hypothesize",
            title: payload["title"] ?? defaultTitle(for: "debug_hypothesize"),
            detail: payload["detail"] ?? payload["status"],
            payload: payload,
            timestamp: timestamp,
            phase: phaseForType("debug_hypothesize", payload: payload),
            isRunning: runningStateForType("debug_hypothesize", payload: payload),
            groupId: payload["group_id"] ?? payload["tool_call_id"]
        )))
        return events
    }

    static func normalizeDebugMark(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        var events: [NormalizedEvent] = []
        if let markerPayload = parseDebugMarkPayload(payload: payload) {
            events.append(.debugMark(markerPayload))
        }
        events.append(.taskActivity(TaskActivity(
            type: "debug_mark",
            title: payload["title"] ?? defaultTitle(for: "debug_mark"),
            detail: payload["detail"] ?? payload["marker_info"],
            payload: payload,
            timestamp: timestamp,
            phase: phaseForType("debug_mark", payload: payload),
            isRunning: runningStateForType("debug_mark", payload: payload),
            groupId: payload["group_id"] ?? payload["tool_call_id"]
        )))
        return events
    }

    static func normalizeDebugInstrument(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        var events: [NormalizedEvent] = []
        if let instrumentPayload = parseDebugInstrumentPayload(payload: payload) {
            events.append(.debugInstrument(instrumentPayload))
        }
        events.append(.taskActivity(TaskActivity(
            type: "debug_instrument",
            title: payload["title"] ?? defaultTitle(for: "debug_instrument"),
            detail: payload["detail"] ?? payload["expression"],
            payload: payload,
            timestamp: timestamp,
            phase: phaseForType("debug_instrument", payload: payload),
            isRunning: runningStateForType("debug_instrument", payload: payload),
            groupId: payload["group_id"] ?? payload["tool_call_id"]
        )))
        return events
    }

    static func normalizeDebugClean(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        var events: [NormalizedEvent] = []
        if let cleanPayload = parseDebugCleanPayload(payload: payload) {
            events.append(.debugClean(cleanPayload))
        }
        events.append(.taskActivity(TaskActivity(
            type: "debug_clean",
            title: payload["title"] ?? defaultTitle(for: "debug_clean"),
            detail: payload["detail"],
            payload: payload,
            timestamp: timestamp,
            phase: phaseForType("debug_clean", payload: payload),
            isRunning: runningStateForType("debug_clean", payload: payload),
            groupId: payload["group_id"] ?? payload["tool_call_id"]
        )))
        return events
    }

    static func normalizeDebugSession(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        var events: [NormalizedEvent] = []
        if let sessionPayload = parseDebugSessionPayload(payload: payload) {
            events.append(.debugSession(sessionPayload))
        }
        events.append(.taskActivity(TaskActivity(
            type: "debug_session",
            title: payload["title"] ?? defaultTitle(for: "debug_session"),
            detail: payload["detail"],
            payload: payload,
            timestamp: timestamp,
            phase: phaseForType("debug_session", payload: payload),
            isRunning: runningStateForType("debug_session", payload: payload),
            groupId: payload["group_id"] ?? payload["tool_call_id"]
        )))
        return events
    }

    static func normalizeDebugQuery(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        var events: [NormalizedEvent] = []
        if let queryPayload = parseDebugQueryPayload(payload: payload) {
            events.append(.debugQuery(queryPayload))
        }
        events.append(.taskActivity(TaskActivity(
            type: "debug_query",
            title: payload["title"] ?? defaultTitle(for: "debug_query"),
            detail: payload["detail"],
            payload: payload,
            timestamp: timestamp,
            phase: phaseForType("debug_query", payload: payload),
            isRunning: runningStateForType("debug_query", payload: payload),
            groupId: payload["group_id"] ?? payload["tool_call_id"]
        )))
        return events
    }

    static func normalizeActivatePlanMode(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        let reason = payload["reason"]
        return [
            .activatePlanMode(reason: reason),
            .taskActivity(TaskActivity(
                type: "activate_plan_mode",
                title: "Plan mode auto-activated",
                detail: reason,
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: false
            ))
        ]
    }

    static func normalizeActivateDebugMode(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        let reason = payload["reason"]
        return [
            .activateDebugMode(reason: reason),
            .taskActivity(TaskActivity(
                type: "activate_debug_mode",
                title: "Debug mode auto-activated",
                detail: reason,
                payload: payload,
                timestamp: timestamp,
                phase: .executing,
                isRunning: false
            ))
        ]
    }
}
