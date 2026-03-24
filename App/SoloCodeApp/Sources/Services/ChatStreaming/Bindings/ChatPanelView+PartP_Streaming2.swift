import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func mainChatTraceLoggingEnabled() -> Bool {
    let env = ProcessInfo.processInfo.environment["SOLOCODE_STREAM_TRACE"] ?? ""
    return env == "1" || env.lowercased() == "true"
}

func mainChatTraceLog(_ message: @autoclosure () -> String) {
    guard mainChatTraceLoggingEnabled() else { return }
    NSLog("[MainChatTrace] %@", message())
}

func policyAckPayloadFromEvent(
    type: String,
    payload: [String: String]
) -> [String: String]? {
    let normalizedType = type
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if normalizedType == "policy_ack" {
        return payload
    }
    guard normalizedType == "mcp_tool_call" else { return nil }
    let tool = (payload["mcp_tool"] ?? payload["tool"] ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let normalizedTool = tool
        .replacingOccurrences(of: "functions.", with: "")
        .replacingOccurrences(of: "function.", with: "")
    guard normalizedTool == "coderide_policy_ack" || normalizedTool == "policy_ack" else {
        return nil
    }
    let hash = (payload["hash"] ?? payload["policy_hash"] ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !hash.isEmpty else { return nil }
    return [
        "hash": hash,
        "title": payload["title"] ?? "Policy acknowledged",
        "detail": payload["detail"] ?? "Policy hash accepted via MCP tool call",
    ]
}

func mainChatInlineReasoningGroupId(
    providerId: String,
    payload: [String: String]
) -> String {
    if let explicit = payload["group_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !explicit.isEmpty,
       explicit == "codex-intermediate-turns" {
        return explicit
    }
    let normalizedProvider = providerId
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if normalizedProvider.isEmpty {
        return "reasoning-stream"
    }
    return "reasoning-stream"
}

@MainActor
func promotedAssistantUpdateContent(
    currentVisibleText: String,
    incomingRawOutput: String
) -> String? {
    let looseBoundary = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    let cleaned = ChatStore.stripCoderideMarkers(incomingRawOutput, aggressive: true)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return nil }

    let current = currentVisibleText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !current.isEmpty else { return cleaned }
    let looseCurrent = current.trimmingCharacters(in: looseBoundary)
    let looseCleaned = cleaned.trimmingCharacters(in: looseBoundary)

    if current == cleaned
        || current.contains(cleaned)
        || (!looseCleaned.isEmpty && (looseCurrent == looseCleaned || looseCurrent.hasPrefix(looseCleaned)))
    {
        return nil
    }
    if cleaned.hasPrefix(current) || cleaned.contains(current) {
        return cleaned
    }
    return cleaned
}

extension ChatPanelView {
    internal func handleRawStreamEvent(
        type t: String, payload p: [String: String], providerId pid: String,
        conversationId convId: UUID?,
        shouldApplyPipelineArtifacts: Bool = true,
        shouldUpdateInlineReasoningVisuals: Bool = true
    ) {
        if t == "reasoning" {
            print("[REASONING_ENTRY] handleRawStreamEvent ENTERED with type=reasoning conv=\(convId?.uuidString.prefix(8) ?? "nil")")
        }
        if t == "assistant_update"
            || t == "turn_started"
            || t == "turn_completed"
            || t == "command_execution"
            || t == "mcp_tool_call"
        {
            mainChatTraceLog(
                "raw type=\(t) provider=\(pid) conv=\(convId?.uuidString.lowercased() ?? "-") title=\(p["title"] ?? "-") detail=\(p["detail"] ?? "-") status=\(p["status"] ?? "-")"
            )
        }
        if let ackPayload = policyAckPayloadFromEvent(type: t, payload: p) {
            let enriched = processPolicyAckEvent(payload: ackPayload, providerId: pid, conversationId: convId)
            recordTaskActivity(type: "policy_ack", payload: enriched, providerId: pid, conversationId: convId)
            if policyAckDisposition(status: enriched["status"]) == .acknowledged {
                flushPolicyAckBlockedQueue(providerId: pid, conversationId: convId)
            }
        }
        if t == "policy_ack" {
            let enriched = processPolicyAckEvent(payload: p, providerId: pid, conversationId: convId)
            recordTaskActivity(type: t, payload: enriched, providerId: pid, conversationId: convId)
            switch policyAckDisposition(status: enriched["status"]) {
            case .acknowledged:
                flushPolicyAckBlockedQueue(providerId: pid, conversationId: convId)
            case .invalid:
                appendTechnicalErrorMessage(
                    "[Policy error] Invalid AGENTS/SKILL acknowledgment received. Expected hash \(enriched["expected_hash"] ?? "?").",
                    in: convId
                )
                stopTaskForPolicyViolation(conversationId: convId)
            case .ignored:
                break
            }
            return
        }
        if shouldHardBlockForMissingPolicyAck(
            type: t,
            payload: p,
            providerId: pid,
            conversationId: convId
        ) {
            // Queue the event instead of silently dropping it.
            // It will be flushed when the policy_ack arrives.
            if let turn = resolveToolTraceTurn(conversationId: convId, providerId: pid) {
                toolRuntime.policyAckBlockedQueue[turn.assistantMessageId, default: []].append(
                    (
                        type: t,
                        payload: p,
                        providerId: pid,
                        conversationId: convId,
                        shouldApplyPipelineArtifacts: shouldApplyPipelineArtifacts
                    )
                )
            }
            return
        }
        updateToolStartRequirementsStateIfNeeded(
            type: t,
            payload: p,
            providerId: pid,
            conversationId: convId
        )
        if shouldHardBlockForMissingTodoOrPlan(
            type: t,
            payload: p,
            providerId: pid,
            conversationId: convId
        ) {
            return
        }
        if t == "tool_validation_error",
           isMCPEditRequiredViolation(payload: p) {
            var enriched = p
            enriched["status"] = "failed"
            if (enriched["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                enriched["title"] = "MCP-only editing policy violation"
            }
            if (enriched["detail"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                enriched["detail"] = "Edit requests must use the coderide MCP tools."
            }
            recordTaskActivity(type: t, payload: enriched, providerId: pid, conversationId: convId)
            emitMCPEditRequiredViolation(payload: enriched, conversationId: convId)
            return
        }
        _ = handleSyntheticCodeReviewToolEvent(
            type: t,
            payload: p,
            conversationId: convId
        )
        if t == "turn_started" {
            startAutoTodoPlaceholderIfNeeded(
                providerId: pid,
                conversationId: convId
            )
            streaming.streamingSegmentTurnIndex += 1
            resetReasoningMessageState(for: convId)
            if shouldUseLinearChat(providerId: pid) {
                splitStreamingMessageForNewTurn(conversationId: convId, providerId: pid)
            }
        }
        let pipelineConversationId = convId ?? conversationId
        if shouldApplyPipelineArtifacts,
           let pipelineTarget = currentAssistantPipelineTarget(for: pipelineConversationId),
           let pipelineConversationId
        {
            let pipelineEvents = RawArtifactEventAdapter.events(
                rawType: t,
                payload: p,
                conversationId: pipelineConversationId,
                assistantMessageId: pipelineTarget.messageId,
                turnId: pipelineTarget.turnId,
                providerId: pid
            )
            if !pipelineEvents.isEmpty {
                applyChatPipelineEvents(pipelineEvents)
            }
        }
        let isSwarmReasoning = t == "reasoning" && SwarmMetadata.isSwarmEvent(p)
        if isSwarmReasoning, let output = p["output"], !output.isEmpty {
            var reasoningPayload = p
            reasoningPayload["title"] = reasoningPayload["title"] ?? "Thinking"
            reasoningPayload["detail"] = String(output.prefix(120))
            reasoningPayload["text"] = output
            reasoningPayload["status"] = reasoningPayload["status"] ?? "running"
            reasoningPayload["phase"] = "thinking"
            recordTaskActivity(
                type: "subagent_text",
                payload: reasoningPayload,
                providerId: pid,
                conversationId: convId
            )
            return
        }
        // Ultra-early reasoning check — fires for ANY event type to confirm arrival
        if t == "reasoning" {
            print("[REASONING_EARLY] reasoning event ARRIVED in handleRawStreamEvent! output_present=\(p["output"] != nil) len=\(p["output"]?.count ?? 0)")
        }
        if t == "reasoning", let output = p["output"], !output.isEmpty {
            print("[REASONING_DEBUG] GOT reasoning event len=\(output.count) provider=\(pid) shouldUpdateVisuals=\(shouldUpdateInlineReasoningVisuals) conv=\(convId?.uuidString.prefix(8) ?? "nil")")
            guard shouldUpdateInlineReasoningVisuals else {
                print("[REASONING_DEBUG] BLOCKED by shouldUpdateInlineReasoningVisuals=false")
                recordTaskActivity(type: t, payload: p, providerId: pid, conversationId: convId)
                return
            }
            let splitThinking = shouldSplitThinkingMessages(providerId: pid)
            print("[REASONING_DEBUG] shouldSplitThinkingMessages=\(splitThinking)")
            if splitThinking {
                let groupId = p["group_id"] ?? "reasoning-stream"
                upsertSeparateThinkingMessage(
                    output: output,
                    groupId: groupId,
                    conversationId: convId
                )
                if convId == self.conversationId {
                    streaming.streamingReasoningText = nil
                    streaming.streamingReasoningConversationId = nil
                    streaming.streamingReasoningBlocks = []
                    streaming.streamingSegments.removeAll { segment in
                        if case .reasoning = segment.kind {
                            return true
                        }
                        return false
                    }
                }
            } else {
                let shouldUpdateVisibleReasoning = shouldUpdateInlineReasoningState(
                    eventConversationId: convId,
                    selectedConversationId: self.conversationId
                )
                print("[REASONING_DEBUG] shouldUpdateVisibleReasoning=\(shouldUpdateVisibleReasoning) eventConv=\(convId?.uuidString.prefix(8) ?? "nil") selectedConv=\(self.conversationId?.uuidString.prefix(8) ?? "nil")")
                if shouldUseLinearChat(providerId: pid), shouldUpdateVisibleReasoning {
                    streaming.codexLastReasoningLine = output.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard shouldUpdateVisibleReasoning else {
                    print("[REASONING_DEBUG] BLOCKED by shouldUpdateVisibleReasoning=false")
                    recordTaskActivity(type: t, payload: p, providerId: pid, conversationId: convId)
                    return
                }
                let groupId = mainChatInlineReasoningGroupId(
                    providerId: pid,
                    payload: p
                )
                if streaming.streamingReasoningConversationId != convId {
                    streaming.streamingReasoningBlocks = []
                    streaming.streamingSegments = []
                    streaming.streamingSegmentTurnIndex = 0
                }
                let reducedState = ChatReasoningStreamReducer.apply(
                    output: output,
                    groupId: groupId,
                    state: .init(
                        blocks: streaming.streamingReasoningBlocks,
                        text: streaming.streamingReasoningText,
                        segments: streaming.streamingSegments
                    ),
                    sequentialStreamingLayoutEnabled: sequentialStreamingLayoutEnabled,
                    streamingSegmentTurnIndex: streaming.streamingSegmentTurnIndex
                )
                streaming.streamingReasoningBlocks = reducedState.blocks
                streaming.streamingReasoningText = reducedState.text
                streaming.streamingSegments = reducedState.segments
                streaming.streamingReasoningConversationId = convId
                print("[REASONING_DEBUG] AFTER reducer: blocks=\(reducedState.blocks.count) text=\(reducedState.text?.count ?? 0) segments=\(reducedState.segments.count)")
                // Save reasoning to the message immediately so ChatTurnView
                // can display it during streaming (not just after stop).
                if let text = reducedState.text, !text.isEmpty {
                    chatStore.saveReasoningToLastAssistant(reasoning: text, in: convId)
                }
            }
        }
        if t == "coderide_show_task_panel" { enableTaskPanelIfNeeded() }
        if t == "coderide_show_swarm_panel",
           planFlowPhase != .building,
           showSwarmPanel,
           shouldAutoOpenSwarmPanelForEvent(
               eventConversationId: convId,
               selectedConversationId: selectedConversationId
           ),
           let swarmId = SwarmMetadata.swarmId(from: p) {
            // Keep panel opening user-driven: if the swarm panel is already open,
            // only sync the selected swarm/card target.
            selectedSwarmId = swarmId
        }
        if t == "swarm_steps", let s = p["steps"], !s.isEmpty {
            let n = s.split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            if let scopedConversationId = convId ?? selectedConversationId {
                swarmProgressStore.setSteps(n, conversationId: scopedConversationId)
            }
        }
        if t == "agent" {
            let title = p["title"] ?? p["agent_name"] ?? "Agent"
            let detail = p["detail"] ?? "started"
            let scopedConversationId = convId ?? selectedConversationId

            // Ensure swarm_id exists — auto-generate from provider + conversation
            // so SwarmLiveReducer creates a visible subagent card.
            var enrichedPayload = p
            if enrichedPayload["swarm_id"] == nil && enrichedPayload["swarmId"] == nil {
                let autoSwarmId = "swarm-\(pid)-\(scopedConversationId?.uuidString.prefix(8) ?? "unknown")"
                enrichedPayload["swarm_id"] = autoSwarmId
                enrichedPayload["group_id"] = autoSwarmId
            }
            if enrichedPayload["agent_name"] == nil {
                enrichedPayload["agent_name"] = title
            }

            if detail == "started" {
                if let scopedConversationId {
                    swarmProgressStore.markStarted(name: title, conversationId: scopedConversationId)
                }
            } else if detail == "completed" {
                if let scopedConversationId {
                    swarmProgressStore.markCompleted(name: title, conversationId: scopedConversationId)
                }
            }

            // Record as task activity so SwarmLiveReducer creates a card.
            // This makes subagent cards appear in chat timeline and swarm panel
            // for ALL providers (Claude CLI, Codex, Kilo, Gemini).
            recordTaskActivity(
                type: "agent",
                payload: enrichedPayload,
                providerId: pid,
                conversationId: scopedConversationId
            )
        }
        if t == "usage",
           let inpStr = p["input_tokens"], let outStr = p["output_tokens"],
           let inp = Int(inpStr), let out = Int(outStr) {
            if pid.hasSuffix("-api") {
                providerUsageStore.addApiUsage(
                    inputTokens: inp,
                    outputTokens: out,
                    model: p["model"] ?? "gpt-4o-mini"
                )
            } else if pid == "claude-cli" {
                let current = providerUsageStore.claudeUsage
                let merged = ClaudeUsage(
                    sessionCost: current?.sessionCost,
                    inputTokens: max(current?.inputTokens ?? 0, inp),
                    outputTokens: max(current?.outputTokens ?? 0, out),
                    cacheReadTokens: current?.cacheReadTokens,
                    cacheWriteTokens: current?.cacheWriteTokens,
                    totalDuration: current?.totalDuration
                )
                providerUsageStore.claudeUsage = merged
                providerUsageStore.claudeUsageMessage = nil
            }
            let prev = chatStore.conversation(for: convId)?.lastInputTokens ?? 0
            if inp > prev {
                chatStore.updateLastInputTokens(inp, for: convId)
            }
        }
        if t == "subagent_batch_done" {
            autoCompleteInProgressTodoAfterSubagents(
                status: p["status"] ?? "done",
                payload: p,
                conversationId: convId
            )
            return // Don't record this synthetic event as a visible activity
        }
        // assistant_update remains an internal progress signal.
        // Visible assistant content must come from textDelta/textReplace,
        // otherwise reasoning/progress text leaks into the normal chat body.
        if t == "assistant_update",
           let output = p["output"],
           !output.isEmpty
        {
            mainChatTraceLog("assistant_update kept_internal chars=\(output.count)")
        }
        // Handle tool_finish: merge result payload into the existing tool trace
        // card so that linesAdded/linesRemoved/output appear in the inline card.
        if t == "tool_finish", let toolUseId = p["id"], !toolUseId.isEmpty {
            if let turn = resolveToolTraceTurn(conversationId: convId, providerId: pid) {
                toolTraceStore.mergeResultIntoLastEvent(
                    toolUseId: toolUseId,
                    conversationId: turn.conversationId,
                    assistantMessageId: turn.assistantMessageId,
                    resultPayload: p
                )
            }
            return  // Don't create a separate trace event for tool_finish
        }
        // Log ALL raw event types to see what the pipeline receives
        if t != "reasoning" && t != "usage" {
            print("[ChatDebug] rawEvent type=\(t) keys=\(p.keys.sorted().joined(separator: ","))")
        }
        // Enrich file-change events with a diff preview when old_string/new_string
        // are present (e.g. str_replace, edit). Claude CLI events bypass the
        // ProviderToolEventMapper so we generate the diff inline.
        var enrichedPayload = p
        if enrichedPayload["diffPreview"] == nil,
           let oldStr = p["old_string"], !oldStr.isEmpty {
            let newStr = p["new_string"] ?? p["content"] ?? p["contents"] ?? ""
            let oldLines = oldStr.components(separatedBy: .newlines)
            let newLines = newStr.components(separatedBy: .newlines)
            let commonPrefix = zip(oldLines, newLines).prefix(while: { $0 == $1 }).count
            var diff = ["--- old", "+++ new"]
            for line in oldLines.dropFirst(commonPrefix).prefix(80) { diff.append("-\(line)") }
            for line in newLines.dropFirst(commonPrefix).prefix(80) { diff.append("+\(line)") }
            enrichedPayload["diffPreview"] = String(diff.joined(separator: "\n").prefix(12_000))
        }
        recordTaskActivity(type: t, payload: enrichedPayload, providerId: pid, conversationId: convId)
    }

    @MainActor
    internal func autoCompleteInProgressTodoAfterSubagents(
        status: String,
        payload: [String: String],
        conversationId: UUID?
    ) {
        let normalizedStatus = status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let targetStatus: TodoStatus = normalizedStatus == "done" ? .done : .blocked
        let excludeCanonicalTodos = isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
        let targetIDs = todoIDsToAutoCompleteAfterSubagentBatch(
            todos: todoStore.todos,
            conversationId: conversationId,
            includePendingReviewTodo: shouldAutoCompletePendingReviewTodo(
                subagentBatchPayload: payload
            ),
            excludeCanonicalTodos: excludeCanonicalTodos
        )
        for id in targetIDs {
            todoStore.setStatus(id: id, status: targetStatus)
        }
    }

}
