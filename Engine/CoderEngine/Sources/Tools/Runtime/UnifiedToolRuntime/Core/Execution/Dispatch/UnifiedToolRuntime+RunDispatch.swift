import Foundation

extension UnifiedToolRuntime {
    public func execute(_ call: ToolCall, context: ToolExecutionContext) async -> [StreamEvent] {
        let normalizedName = normalizeToolName(call.name)
        let policy = context.policy

        // Budget enforcement (defense-in-depth — ToolEnabledLLMProvider also enforces)
        if toolCallsInCurrentRound >= policy.maxToolCallsPerRound {
            return [.raw(type: "tool_execution_error", payload: [
                "tool_call_id": call.id,
                "tool": normalizedName,
                "title": "Tool budget exceeded",
                "detail": "Reached tool limit per round (\(policy.maxToolCallsPerRound))",
                "status": "failed",
                "error_code": "budget_exceeded"
            ])]
        }
        let exemptFromRepetitionLimit = Self.readOnlyFileToolsExemptFromRepetitionLimit.contains(normalizedName)
        let nameCount = toolCallCountByName[normalizedName, default: 0]
        if !exemptFromRepetitionLimit, nameCount >= policy.maxRepeatedSameToolPerRound {
            return [.raw(type: "tool_execution_error", payload: [
                "tool_call_id": call.id,
                "tool": normalizedName,
                "title": "Tool repetition limit",
                "detail": "Tool '\(normalizedName)' exceeded per-round limit (\(policy.maxRepeatedSameToolPerRound))",
                "status": "failed",
                "error_code": "repetition_exceeded"
            ])]
        }
        toolCallsInCurrentRound += 1
        if !exemptFromRepetitionLimit {
            toolCallCountByName[normalizedName, default: 0] += 1
        }

        let start = Date()
        let basePayload = buildBasePayload(call: call, normalizedName: normalizedName)
        let startEventType = startEventTypeForTool(name: normalizedName, payload: basePayload)

        var events: [StreamEvent] = [.raw(type: startEventType, payload: basePayload)]
        let result = await run(call, normalizedName: normalizedName, context: context, startDate: start)

        var completedPayload = result.payload
        completedPayload["tool_call_id"] = call.id
        completedPayload["tool"] = normalizedName
        completedPayload["duration_ms"] = "\(result.durationMs)"
        let existingStatus = (completedPayload["status"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if result.ok {
            if existingStatus.isEmpty {
                completedPayload["status"] = "completed"
            }
        } else {
            completedPayload["status"] = "failed"
        }
        if let swarmId = call.swarmId, !swarmId.isEmpty {
            completedPayload["swarm_id"] = swarmId
            completedPayload["group_id"] = "swarm-\(swarmId)"
        }

        let eventType = eventTypeForTool(name: normalizedName, ok: result.ok, payload: completedPayload)
        events.append(.raw(type: eventType, payload: completedPayload))
        if completedPayload["is_mcp"] == "true" {
            events.append(
                contentsOf: Self.syntheticIDEStateEventsFromMCP(
                    call: call,
                    completedPayload: completedPayload
                )
            )
        }

        // Auto-reindex modified files so semantic search stays fresh
        if result.ok, UnifiedToolRuntime.fileChangingTools.contains(normalizedName) {
            await reindexModifiedFile(call: call, context: context)
        }

        return events
    }

}
