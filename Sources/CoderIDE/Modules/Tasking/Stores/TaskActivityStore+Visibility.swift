import Foundation

@MainActor
extension TaskActivityStore {
    static let hiddenGenericTypes: Set<String> = [
        "reasoning",
        "thinking",
        "analysis",
        "deliberation",
        "turn_started",
        "turn_completed",
        "usage",
    ]

    static let hiddenGenericTypePrefixes: [String] = [
        "reasoning_",
        "thinking_",
        "analysis_",
        "trace_",
        "internal_",
        "usage_",
    ]

    static let concreteTypes: Set<String> = [
        "agent",
        "bash",
        "command_execution",
        "edit",
        "error",
        "file_change",
        "instant_grep",
        "mcp_tool_call",
        "permission_denied",
        "plan_step",
        "plan_step_update",
        "plan_create",
        "plan_read",
        "plan_step_upsert",
        "plan_step_batch_update",
        "plan_step_reorder",
        "plan_step_dependency_set",
        "plan_set_walkthrough",
        "plan_history_read",
        "plan_diff",
        "plan_request_user_input",
        "planning_auto_reset",
        "activate_plan_mode",
        "activate_debug_mode",
        "debug_phase_update",
        "debug_user_request",
        "debug_resolved",
        "debug_log",
        "debug_query",
        "debug_session",
        "debug_hypothesize",
        "debug_mark",
        "debug_clean",
        "debug_trace_analyze",
        "debug_instrument",
        "debug_timeline",
        "debug_snapshot",
        "debug_test_check",
        "process_paused",
        "process_resumed",
        "read_batch_started",
        "read_batch_completed",
        "review-worker-plan",
        "review-fix-round",
        "swarm_delegation_skipped",
        "tool_execution_error",
        "tool_timeout",
        "tool_validation_error",
        "todo_read",
        "todo_write",
        "web_search",
        "web_search_started",
        "web_search_completed",
        "web_search_failed",
        "web_fetch",
        "web_fetch_started",
        "web_fetch_completed",
        "web_fetch_failed",
        "semantic_search",
        "read_lints",
        "debug_context",
        "debug_native_session",
        "skill_invocation",
        "subagent_text",
    ]

    static func isConcreteVisibleEventType(_ type: String) -> Bool {
        let normalized = normalizedEventType(type)
        if isHiddenGenericType(normalized) {
            return false
        }
        if concreteTypes.contains(normalized) {
            return true
        }
        if normalized.hasPrefix("web_search")
            || normalized.hasPrefix("web_fetch")
            || normalized.hasPrefix("todo_")
            || normalized.hasPrefix("read_batch")
            || normalized.hasPrefix("plan_step")
            || normalized.hasPrefix("plan_")
        {
            return true
        }
        return false
    }

    static func isConcreteVisibleEvent(_ activity: TaskActivity) -> Bool {
        let normalized = normalizedEventType(activity.type)
        if isHiddenGenericType(normalized) {
            return false
        }
        if normalized == "mcp_tool_call" {
            return ToolTraceVisibility.isMCPEvent(activity: activity)
        }
        if isConcreteVisibleEventType(activity.type) {
            return true
        }
        return !(activity.payload["command"] ?? "").isEmpty
            || !(activity.payload["path"] ?? "").isEmpty
            || !(activity.payload["file"] ?? "").isEmpty
            || !(activity.payload["query"] ?? "").isEmpty
            || !(activity.payload["tool"] ?? "").isEmpty
    }

    static func concreteRecentActivities(activities: [TaskActivity], limit: Int) -> [TaskActivity] {
        guard limit > 0 else { return [] }
        return activities.filter { Self.isConcreteVisibleEvent($0) }.suffix(limit).map { $0 }
    }

    static func concreteRecentActivities(
        from store: TaskActivityStore,
        limit: Int
    ) -> [TaskActivity] {
        Self.concreteRecentActivities(activities: store.activities, limit: limit)
    }

    func concreteRecentActivities(limit: Int) -> [TaskActivity] {
        Self.concreteRecentActivities(activities: activities, limit: limit)
    }

    static func lastConcreteVisibleActivity(in activities: [TaskActivity]) -> TaskActivity? {
        activities.last(where: isConcreteVisibleEvent(_:))
    }

    /// Last visible activity from the **main agent** only (excludes subagent events).
    static func lastConcreteNonSwarmActivity(in activities: [TaskActivity]) -> TaskActivity? {
        activities.last { isConcreteVisibleEvent($0) && !SwarmMetadata.isSwarmEvent($0.payload) }
    }

    static func streamingStatusText(isPaused: Bool, activities: [TaskActivity]) -> String {
        if isPaused { return "Paused" }
        guard let last = lastConcreteNonSwarmActivity(in: activities)
                ?? lastConcreteVisibleActivity(in: activities) else {
            return "Thinking"
        }

        if !last.isRunning {
            let elapsed = Date().timeIntervalSince(last.timestamp)
            if elapsed > 1.5 {
                return "Thinking"
            }
            return "Planning next move"
        }

        let normalizedType = last.type.lowercased()
        if normalizedType.contains("read") || normalizedType.contains("glob") {
            return "Reading files"
        }
        if normalizedType.contains("grep") || normalizedType.contains("search") {
            return "Searching codebase"
        }
        if normalizedType.contains("edit") || normalizedType.contains("write") || normalizedType.contains("file_change") {
            return "Editing code"
        }
        if normalizedType.contains("bash") || normalizedType.contains("command") {
            return "Running command"
        }
        if normalizedType.contains("mcp") {
            let tool = (last.payload["tool"] ?? last.payload["mcp_tool"] ?? "").lowercased()
            switch tool {
            case "mcp_batch": return "Running MCP batch"
            case "mcp_list_resources": return "Listing MCP resources"
            case "mcp_read_resource": return "Reading MCP resource"
            case "mcp_subscribe": return "Subscribing to resource"
            case "mcp_list_prompts": return "Listing MCP prompts"
            case "mcp_get_prompt": return "Resolving MCP prompt"
            case "mcp_logs": return "Reading MCP logs"
            case "mcp_restart_server": return "Restarting MCP server"
            case "mcp_health": return "Checking MCP health"
            default: return "Calling MCP tool"
            }
        }
        if normalizedType == "subagent_text" {
            let source = (last.payload["source"] ?? "").lowercased()
            return source == "reasoning" ? "Subagent thinking" : "Subagent output"
        }
        if normalizedType.contains("web_search") {
            return "Searching web"
        }
        if normalizedType.contains("web_fetch") {
            return "Fetching page"
        }
        if normalizedType.hasPrefix("debug_") {
            let tool = (last.payload["tool"] ?? last.payload["name"] ?? normalizedType).lowercased()
            switch tool {
            case "debug_trace_analyze": return "Analyzing trace"
            case "debug_instrument": return "Instrumenting code"
            case "debug_timeline": return "Building timeline"
            case "debug_snapshot": return "Capturing snapshot"
            case "debug_test_check": return "Checking tests"
            case "debug_context": return "Gathering context"
            case "debug_log": return "Logging observation"
            case "debug_query": return "Querying logs"
            case "debug_hypothesize": return "Hypothesizing"
            case "debug_mark": return "Placing marker"
            case "debug_clean": return "Cleaning markers"
            case "debug_session": return "Managing session"
            case "debug_set_phase": return "Updating phase"
            case "debug_resolve": return "Resolving"
            default: return "Debugging"
            }
        }
        if normalizedType.contains("todo") || normalizedType.contains("plan_step") || normalizedType.hasPrefix("plan_") {
            return "Planning next move"
        }
        switch last.phase {
        case .executing: return "Running"
        case .editing: return "Editing"
        case .searching: return "Searching"
        case .planning: return "Planning next move"
        case .thinking: return "Thinking"
        }
    }

    static func streamingDetailText(
        activities: [TaskActivity],
        activeOperationsCount: Int
    ) -> String? {
        guard let last = lastConcreteVisibleActivity(in: activities) else { return nil }
        if activeOperationsCount > 1 {
            return "\(last.title) • \(activeOperationsCount) operations"
        }
        return last.title
    }

    static func streamingDetailText(
        in store: TaskActivityStore,
        activeOperationsCount: Int
    ) -> String? {
        streamingDetailText(
            activities: store.activities,
            activeOperationsCount: activeOperationsCount
        )
    }

    static func assistantUpdateText(in activities: [TaskActivity]) -> String? {
        guard let latest = activities.last(where: {
            normalizedEventType($0.type) == "assistant_update"
        }) else {
            return nil
        }

        let raw = latest.detail
            ?? latest.payload["detail"]
            ?? latest.payload["output"]
            ?? latest.title
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > 120 {
            return String(trimmed.prefix(117)) + "..."
        }
        return trimmed
    }

    private static func normalizedEventType(_ type: String) -> String {
        type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func isHiddenGenericType(_ normalizedType: String) -> Bool {
        if hiddenGenericTypes.contains(normalizedType) {
            return true
        }
        return hiddenGenericTypePrefixes.contains { normalizedType.hasPrefix($0) }
    }
}
