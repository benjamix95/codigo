import Foundation

extension ToolEnabledLLMProvider {
    /// Resolve a tool call (from native tool_call_suggested) into stream events.
    /// IDE-state tools are emitted as raw events; everything else goes through UnifiedToolRuntime.
    /// `preEmittedSubagentIds` maps tool_call_id → subagent_id for subagents whose "started"
    /// event was already emitted by the caller (parallel batch execution).
    /// `onLiveSubagentEvent` is called for intermediate subagent events during execution,
    /// enabling real-time card updates before the subagent fully completes.
    func events(
        for marker: CoderIDEMarker,
        context: WorkspaceContext,
        preEmittedSubagentIds: [String: String]? = nil,
        onLiveSubagentEvent: (@Sendable (StreamEvent) -> Void)? = nil
    ) async -> [StreamEvent] {
        guard marker.kind == "tool_call" else { return [] }
        let toolName = inferredToolName(from: marker.payload)
        guard !toolName.isEmpty else { return [] }

        if let legacyInvokeEvents = await executeLegacyInvokeSwarmIfNeeded(
            marker: marker,
            toolName: toolName,
            context: context
        ) {
            return legacyInvokeEvents
        }

        if let enforcementEvents = await enforcedMCPEditEventsIfNeeded(
            marker: marker,
            toolName: toolName,
            context: context
        ) {
            return enforcementEvents
        }

        // IDE state tools — pass-through as raw events, not executed through runtime
        switch toolName {
        case "todo_read":
            return [.raw(type: "todo_read", payload: [:])]
        case "todo_write":
            return [.raw(type: "todo_write", payload: marker.payload)]
        case "policy_ack":
            return [.raw(type: "policy_ack", payload: marker.payload)]
        case "plan_step_update":
            return [.raw(type: "plan_step_update", payload: marker.payload)]
        case "debug_panel":
            return [.raw(type: "tool_validation_error", payload: [
                "title": "Legacy debug_panel is not supported",
                "detail": "Use debug_set_phase, debug_request_user, debug_resolve",
                "status": "failed",
                "error_code": "legacy_debug_panel_removed",
                "tool": "debug_panel",
            ])]
        case "debug_set_phase":
            return [.raw(type: "debug_phase_update", payload: marker.payload)]
        case "debug_request_user":
            return [.raw(type: "debug_user_request", payload: marker.payload)]
        case "debug_resolve":
            return [.raw(type: "debug_resolved", payload: marker.payload)]
        case "mermaid_render":
            return [.raw(type: "mermaid_render", payload: marker.payload)]
        case "activate_plan_mode":
            return [.raw(type: "activate_plan_mode", payload: marker.payload)]
        case "activate_debug_mode":
            return [.raw(type: "activate_debug_mode", payload: marker.payload)]
        case "show_task_panel":
            return [.raw(type: "coderide_show_task_panel", payload: [:])]
        case "show_swarm_panel":
            return [.raw(type: "coderide_show_swarm_panel", payload: marker.payload)]
        default:
            break
        }

        // Subagent tools — execute inline during the agent's streaming loop.
        if toolName.hasPrefix("subagent_") {
            let toolCallId = marker.payload["id"] ?? ""
            let preAssignedId = preEmittedSubagentIds?[toolCallId]
            return await executeSubagentTool(
                toolName: toolName,
                marker: marker,
                context: context,
                preAssignedSubagentId: preAssignedId,
                onLiveEvent: onLiveSubagentEvent
            )
        }

        // Skill tool — invoke a local skill (SKILL.md) via a subagent
        if toolName == "skill" {
            return await executeSkillTool(marker: marker, context: context)
        }

        // All other tools — execute through UnifiedToolRuntime
        let call = ToolCall(
            id: marker.payload["id"] ?? UUID().uuidString,
            name: toolName,
            args: marker.payload,
            sourceProvider: id,
            swarmId: marker.payload["swarm_id"],
            scope: executionScope
        )
        return await runtime.execute(call, context: ToolExecutionContext(workspaceContext: context, policy: policy, executionScope: executionScope))
    }

    func executeLegacyInvokeSwarmIfNeeded(
        marker: CoderIDEMarker,
        toolName: String,
        context: WorkspaceContext
    ) async -> [StreamEvent]? {
        let normalizedTool = ProviderToolEventMapper.normalizeToolIdentifier(toolName)

        // Legacy direct tool call: invoke_swarm(...)
        let isDirectLegacyInvoke = normalizedTool == "invoke_swarm"

        // Legacy MCP wrapper: mcp_call(tool: coderide_invoke_swarm | invoke_swarm, ...)
        let targetMCPTool = ProviderToolEventMapper.normalizeToolIdentifier(
            marker.payload["tool"] ?? marker.payload["mcp_tool"] ?? marker.payload["tool_name"] ?? ""
        )
        let isLegacyInvokeViaMCP = normalizedTool == "mcp_call" && targetMCPTool == "invoke_swarm"

        guard isDirectLegacyInvoke || isLegacyInvokeViaMCP else { return nil }

        guard subagentProviderFactory != nil else {
            return [.raw(type: "tool_validation_error", payload: [
                "id": marker.payload["id"] ?? UUID().uuidString,
                "name": toolName,
                "title": "invoke_swarm non supportato",
                "detail": "invoke_swarm è legacy; usa subagent_* (subagent_explorer/coder/reviewer/...).",
                "status": "failed",
                "error_code": "legacy_invoke_swarm_disabled",
            ])]
        }

        var adaptedPayload = marker.payload
        if (adaptedPayload["task"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let fallbackTask = adaptedPayload["prompt"]
                ?? adaptedPayload["detail"]
                ?? adaptedPayload["query"]
                ?? adaptedPayload["objective"]
                ?? adaptedPayload["goal"]
                ?? ""
            if !fallbackTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                adaptedPayload["task"] = fallbackTask
            }
        }

        guard let task = adaptedPayload["task"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !task.isEmpty else {
            return [.raw(type: "tool_validation_error", payload: [
                "id": marker.payload["id"] ?? UUID().uuidString,
                "name": toolName,
                "title": "Missing task",
                "detail": "invoke_swarm richiede un task non vuoto; usa subagent_* con task.",
                "status": "failed",
                "error_code": "missing_argument",
            ])]
        }

        let role = Self.resolveLegacyInvokeSwarmRole(payload: adaptedPayload, task: task)
        let mappedToolName = ProviderToolEventMapper.normalizeToolIdentifier(role.toolName)
        adaptedPayload["task"] = task
        adaptedPayload["name"] = mappedToolName
        adaptedPayload["tool"] = mappedToolName
        adaptedPayload["tool_name"] = mappedToolName

        let adaptedMarker = CoderIDEMarker(kind: marker.kind, payload: adaptedPayload)
        return await executeSubagentTool(
            toolName: mappedToolName,
            marker: adaptedMarker,
            context: context
        )
    }


}
