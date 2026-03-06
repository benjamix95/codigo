import Foundation

extension CodexCLIProvider {
    private static func shouldEmitSyntheticEventForMCPPayload(_ payload: [String: String]) -> Bool {
        let normalizedStatus = (payload["status"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedStatus.isEmpty {
            return true
        }

        if isTerminalMCPToolStatus(normalizedStatus) {
            return true
        }

        // Keep live lifecycle updates for plan/debug/panel signals, but avoid
        // non-terminal todo writes that can create duplicate optimistic updates.
        let rawTool = (
            payload["mcp_tool"] ?? payload["tool"] ?? payload["tool_raw"] ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTool = normalizeIDEStateMCPTool(rawTool)

        if normalizedTool == "todo_write" {
            return false
        }
        if IDEStateSyntheticEventFactory.knowsTool(normalizedTool) {
            return true
        }
        if normalizedTool.hasPrefix("plan_") {
            return true
        }
        if normalizedTool.hasPrefix("debug_") {
            return true
        }
        if normalizedTool.hasPrefix("subagent_") {
            return true
        }
        switch normalizedTool {
        case "activate_plan_mode", "activate_debug_mode", "show_task_panel", "show_swarm_panel", "mermaid_render", "policy_ack":
            return true
        default:
            return false
        }
    }

    static func parseStreamJSONEvent(
        _ json: [String: Any],
        state: inout CodexStreamParserState
    ) -> [StreamEvent] {
        var events: [StreamEvent] = []
        let eventType = normalizedEventType((json["type"] as? String) ?? "")

        if eventType == "turn.started" {
            events.append(contentsOf: finalizeAssistantTurnIfNeeded(state: &state))
            if !state.cumulativeVisibleText.isEmpty && state.turnCount > 0 {
                events.append(.raw(type: "reasoning", payload: [
                    "output": String(state.cumulativeVisibleText.prefix(6_000)),
                    "title": "Reasoning",
                    "group_id": "codex-intermediate-turns",
                ]))
                events.append(.textReplace(""))
                state.cumulativeVisibleText = ""
            }
            state.turnCount += 1
            state.resetTurn()
            var payload: [String: String] = [
                "title": "Turn started",
                "detail": "Request execution in progress",
                "status": "started",
            ]
            if let turnId = firstString(in: json, keys: ["turn_id", "id"]), !turnId.isEmpty {
                payload["id"] = turnId
                payload["group_id"] = turnId
            }
            appendRawEvent(
                type: "turn_started",
                payload: payload,
                state: &state,
                events: &events
            )
        }

        if eventType == "turn.completed",
           let usage = json["usage"] as? [String: Any],
           let inp = (usage["input_tokens"] as? Int) ?? (usage["prompt_tokens"] as? Int),
           let out = (usage["output_tokens"] as? Int) ?? (usage["completion_tokens"] as? Int) {
            appendRawEvent(
                type: "usage",
                payload: [
                    "input_tokens": "\(inp)",
                    "output_tokens": "\(out)",
                    "model": "codex",
                ],
                state: &state,
                events: &events
            )
        }
        if eventType == "turn.completed" {
            var payload: [String: String] = [
                "title": "Turn completed",
                "detail": "Request execution completed",
                "status": "completed",
            ]
            if let turnId = firstString(in: json, keys: ["turn_id", "id"]), !turnId.isEmpty {
                payload["id"] = turnId
                payload["group_id"] = turnId
            }
            appendRawEvent(
                type: "turn_completed",
                payload: payload,
                state: &state,
                events: &events
            )
        }

        if let rawEvent = parseRawEvent(from: json, workspacePath: state.workspacePath) {
            appendRawEvent(
                type: rawEvent.type,
                payload: rawEvent.payload,
                state: &state,
                events: &events
            )
            // Emit synthetic IDE-state events when an MCP tool call targets
            // coderide_todo_write / coderide_todo_read / coderide_plan_* tools.
            // The MCP tool call event is kept for activity display; the synthetic
            // event feeds the EventNormalizer → TodoStore / PlanBoard pipeline.
            if rawEvent.type == "mcp_tool_call" {
                let shouldEmitSynthetic = shouldEmitSyntheticEventForMCPPayload(rawEvent.payload)
                if shouldEmitSynthetic {
                    let item = (json["item"] as? [String: Any]) ?? json
                    for synthetic in syntheticIDEStateEventsFromMCP(
                        payload: rawEvent.payload,
                        item: item
                    ) {
                        appendRawEvent(
                            type: synthetic.type,
                            payload: synthetic.payload,
                            state: &state,
                            events: &events
                        )
                    }
                }
            }
        }

        captureAssistantUpdateState(from: json, state: &state)
        if let assistantUpdatePayload = extractAssistantUpdatePayload(from: json) {
            appendRawEvent(
                type: "assistant_update",
                payload: assistantUpdatePayload,
                state: &state,
                events: &events
            )
        }

        if !state.emittedContextCompacted, containsCompactionSignal(json: json) {
            state.emittedContextCompacted = true
            appendRawEvent(
                type: "context_compacted",
                payload: [
                    "title": "Automatically compacting context",
                    "detail": "Codex compacted the context natively.",
                ],
                state: &state,
                events: &events
            )
        }

        if let agentChunk = extractAgentMessageChunk(from: json) {
            events.append(
                contentsOf: processAgentMessageChunk(
                    agentChunk.text,
                    isDelta: agentChunk.isDelta,
                    state: &state
                )
            )
        }

        if eventType == "turn.completed" {
            events.append(contentsOf: finalizeAssistantTurnIfNeeded(state: &state))
            state.resetTurn()
        }

        return events
    }

    static func finalizeStreamJSONState(state: inout CodexStreamParserState) -> [StreamEvent] {
        var events: [StreamEvent] = []
        if !state.jsonCarry.isEmpty {
            let (objects, remainder) = extractJSONObjectStringsAndRemainder(from: state.jsonCarry)
            for jsonObject in objects {
                guard let payload = decodeJSONDictionary(jsonObject) else { continue }
                events.append(contentsOf: parseStreamJSONEvent(payload, state: &state))
            }
            if !remainder.isEmpty, let trailing = decodeJSONDictionary(remainder) {
                events.append(contentsOf: parseStreamJSONEvent(trailing, state: &state))
            }
            state.jsonCarry = ""
        }
        events.append(contentsOf: finalizeAssistantTurnIfNeeded(state: &state))
        return events
    }

    static func processAgentMessageChunk(
        _ text: String,
        isDelta: Bool,
        state: inout CodexStreamParserState
    ) -> [StreamEvent] {
        guard !text.isEmpty else { return [] }
        var events: [StreamEvent] = []
        var rawDelta = ""

        if isDelta {
            rawDelta = text
            state.turn.lastObservedAgentText += text
            state.turn.lastValidAgentMessage = state.turn.lastObservedAgentText
        } else {
            let previous = state.turn.lastObservedAgentText
            state.turn.lastObservedAgentText = text
            state.turn.lastValidAgentMessage = text
            if text.hasPrefix(previous) {
                rawDelta = String(text.dropFirst(previous.count))
            } else if previous.hasPrefix(text) {
                rawDelta = ""
            } else {
                rawDelta = text
            }
        }

        if !rawDelta.isEmpty {
            emitMarkerEvents(from: rawDelta, state: &state, events: &events)
            let cleaned = scrubTechnicalTextChunk(rawDelta, carry: &state.scrubCarry)
            if !cleaned.isEmpty {
                state.turn.emittedAnyAssistantDelta = true
                state.cumulativeVisibleText += cleaned
                events.append(.textDelta(cleaned))
            }
        }

        return events
    }
}
