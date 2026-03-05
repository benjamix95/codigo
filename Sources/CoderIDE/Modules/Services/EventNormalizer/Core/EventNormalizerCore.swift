import Foundation

enum EventNormalizer {
    static func normalizeEnvelope(
        sourceProvider: String,
        type: String,
        payload: [String: String],
        timestamp: Date = .now
    ) -> NormalizedEventEnvelope {
        let normalizedType = normalizeSpecialType(type, payload: payload)
        let events = normalize(type: normalizedType, payload: payload, timestamp: timestamp)
        let kind: EventKind
        switch normalizedType {
        case "command_execution", "bash": kind = .terminalSession
        case "file_change", "edit",
             "str_replace", "regex_replace", "write", "write_file", "create_file", "delete_file",
             "parallel_apply", "apply_patch", "rename_symbol", "find_and_replace_all", "undo_edit",
             "multi_edit", "multiedit",
             "notebook_edit", "notebook_write":
            kind = .fileUpdate
        case "turn_started", "turn_completed": kind = .generic
        case "instant_grep", "search",
             "web_search", "web_search_started", "web_search_completed", "web_search_failed",
             "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed": kind = .instantGrep
        case "todo_write", "todo_read": kind = .todoUpdate
        case "plan_step", "plan_step_update": kind = .planStepUpdate
        case "plan_create", "plan_read", "plan_step_upsert", "plan_step_batch_update",
             "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
             "plan_history_read", "plan_diff", "plan_request_user_input":
            kind = .planLifecycle
        case "mermaid_render": kind = .mermaidRender
        case "debug_phase_update": kind = .debugPhaseUpdate
        case "debug_user_request": kind = .debugUserRequest
        case "debug_resolved": kind = .debugResolved
        case "debug_log", "debug_query", "debug_session", "debug_hypothesize", "debug_mark", "debug_clean",
             "debug_trace_analyze", "debug_instrument", "debug_timeline", "debug_snapshot", "debug_test_check":
            kind = .debugToolUpdate
        case "debug_panel", "debug_panel_update":
            kind = .errorDiagnostic
        case "activate_plan_mode", "activate_debug_mode": kind = .modeActivation
        case "swarm_steps", "agent": kind = .swarmProgress
        case "usage": kind = .usageUpdate
        case "tool_execution_error", "tool_validation_error", "tool_timeout", "permission_denied", "error":
            kind = .errorDiagnostic
        default: kind = .generic
        }
        return NormalizedEventEnvelope(
            version: 1,
            sourceProvider: sourceProvider,
            timestamp: timestamp,
            kind: kind,
            payload: payload,
            events: events
        )
    }

    static func normalize(type: String, payload: [String: String], timestamp: Date = .now) -> [NormalizedEvent] {
        var events: [NormalizedEvent] = []

        if type == "reasoning" {
            return []
        }

        if type == "todo_write", let normalized = normalizeTodoWrite(payload: payload, timestamp: timestamp) {
            return normalized
        }

        if type == "todo_read" {
            return normalizeTodoRead(timestamp: timestamp)
        }

        if type == "plan_step" || type == "plan_step_update" {
            return normalizePlanStep(type: type, payload: payload, timestamp: timestamp)
        }

        if isPlanLifecycleType(type) {
            return normalizePlanLifecycleEvent(type: type, payload: payload, timestamp: timestamp)
        }

        if type == "mermaid_render" {
            return normalizeMermaidRender(payload: payload, timestamp: timestamp)
        }

        if type == "debug_phase_update" {
            return normalizeDebugPhaseUpdate(payload: payload, timestamp: timestamp)
        }

        if type == "debug_user_request" {
            return normalizeDebugUserRequest(payload: payload, timestamp: timestamp)
        }

        if type == "debug_resolved" {
            return normalizeDebugResolved(payload: payload, timestamp: timestamp)
        }

        if type == "debug_panel" || type == "debug_panel_update" {
            return normalizeLegacyDebugPanel(payload: payload, timestamp: timestamp)
        }

        if type == "debug_log" {
            return normalizeDebugLog(payload: payload, timestamp: timestamp)
        }

        if type == "debug_hypothesize" {
            return normalizeDebugHypothesize(payload: payload, timestamp: timestamp)
        }

        if type == "debug_mark" {
            return normalizeDebugMark(payload: payload, timestamp: timestamp)
        }

        if type == "debug_instrument" {
            return normalizeDebugInstrument(payload: payload, timestamp: timestamp)
        }

        if type == "debug_clean" {
            return normalizeDebugClean(payload: payload, timestamp: timestamp)
        }

        if type == "debug_session" {
            return normalizeDebugSession(payload: payload, timestamp: timestamp)
        }

        if type == "debug_query" {
            return normalizeDebugQuery(payload: payload, timestamp: timestamp)
        }

        if type == "activate_plan_mode" {
            return normalizeActivatePlanMode(payload: payload, timestamp: timestamp)
        }

        if type == "activate_debug_mode" {
            return normalizeActivateDebugMode(payload: payload, timestamp: timestamp)
        }

        if type == "instant_grep", let grep = parseInstantGrep(payload: payload, timestamp: timestamp) {
            return normalizeInstantGrep(grep: grep, payload: payload, timestamp: timestamp)
        }

        if (type == "command_execution" || type == "bash"), let grep = parseInstantGrepFromCommand(payload: payload, timestamp: timestamp) {
            events.append(.instantGrep(grep))
        }
        if (type == "command_execution" || type == "bash"),
           let syntheticRead = parseReadActivityFromCommand(payload: payload, timestamp: timestamp) {
            events.append(.taskActivity(syntheticRead))
        }

        return normalizeDefault(type: type, payload: payload, events: events, timestamp: timestamp)
    }
}

private extension EventNormalizer {
    static func normalizeDefault(
        type: String,
        payload: [String: String],
        events: [NormalizedEvent],
        timestamp: Date
    ) -> [NormalizedEvent] {
        var output = events

        let normalizedType = EventNormalizer.normalizeSpecialType(type, payload: payload)
        let phase = EventNormalizer.phaseForType(normalizedType, payload: payload)
        let running = EventNormalizer.runningStateForType(normalizedType, payload: payload)

        let resolvedTitleDetail: (title: String, detail: String?) = {
            if normalizedType == "mcp_tool_call", EventNormalizer.isTrustedMCPPayload(payload) {
                return EventNormalizer.mcpTitleAndDetail(payload: payload)
            }
            return (payload["title"] ?? EventNormalizer.defaultTitle(for: normalizedType), payload["detail"])
        }()

        output.append(.taskActivity(TaskActivity(
            type: normalizedType,
            title: EventNormalizer.withSwarmPrefix(resolvedTitleDetail.title, payload: payload),
            detail: resolvedTitleDetail.detail,
            payload: payload,
            timestamp: timestamp,
            phase: phase,
            isRunning: running,
            groupId: payload["group_id"]
                ?? payload["groupId"]
                ?? payload["queryId"]
                ?? payload["query_id"]
                ?? payload["tool_call_id"]
                ?? payload["toolCallId"]
                ?? payload["call_id"]
                ?? payload["callId"]
        )))
        return output
    }
}
