import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func handleRawStreamEvent(
        type t: String, payload p: [String: String], providerId pid: String,
        conversationId convId: UUID?
    ) {
        if t == "policy_ack" {
            let enriched = processPolicyAckEvent(payload: p, providerId: pid, conversationId: convId)
            recordTaskActivity(type: t, payload: enriched, providerId: pid, conversationId: convId)
            flushPolicyAckBlockedQueue(providerId: pid, conversationId: convId)
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
                if !policyAckFailedMessages.contains(turn.assistantMessageId) {
                    policyAckBlockedQueue[turn.assistantMessageId, default: []].append(
                        (type: t, payload: p, providerId: pid, conversationId: convId)
                    )
                }
            }
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
        if t == "turn_started" {
            streamingSegmentTurnIndex += 1
            resetReasoningMessageState(for: convId)
            if shouldUseLinearChat(providerId: pid) {
                splitStreamingMessageForNewTurn(conversationId: convId, providerId: pid)
            }
        }
        if t == "reasoning", let output = p["output"], !output.isEmpty {
            if shouldUseLinearChat(providerId: pid) {
                // For Codex linear chat, reasoning is shown only as streaming
                // status/detail text, never as an inline thinking box.
                if convId == self.conversationId {
                    codexLastReasoningLine = output.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if shouldSplitThinkingMessages(providerId: pid) {
                let groupId = p["group_id"] ?? "reasoning-stream"
                upsertSeparateThinkingMessage(
                    output: output,
                    groupId: groupId,
                    conversationId: convId
                )
                if convId == self.conversationId {
                    streamingReasoningText = nil
                    streamingReasoningConversationId = nil
                    streamingReasoningBlocks = []
                    streamingSegments.removeAll { segment in
                        if case .reasoning = segment.kind {
                            return true
                        }
                        return false
                    }
                }
            } else {
                let groupId = p["group_id"] ?? "reasoning-stream"
                if streamingReasoningConversationId != convId {
                    streamingReasoningBlocks = []
                    streamingSegments = []
                    streamingSegmentTurnIndex = 0
                }
                if let idx = streamingReasoningBlocks.firstIndex(where: { $0.id == groupId }) {
                    streamingReasoningBlocks[idx].text = Self.mergeReasoningText(
                        existing: streamingReasoningBlocks[idx].text,
                        incoming: output
                    )
                } else {
                    streamingReasoningBlocks.append(ReasoningBlock(id: groupId, text: output))
                }
                streamingReasoningText = streamingReasoningBlocks.map(\.text).joined(separator: "\n\n")
                streamingReasoningConversationId = convId

                if sequentialStreamingLayoutEnabled {
                    let segId = "reasoning-\(streamingSegmentTurnIndex)"
                    let currentBlockText = streamingReasoningBlocks.last(where: { $0.id == groupId })?.text ?? output
                    if let segIdx = streamingSegments.firstIndex(where: { $0.id == segId }) {
                        streamingSegments[segIdx].kind = .reasoning(currentBlockText)
                    } else {
                        streamingSegments.append(MessageSegment(id: segId, kind: .reasoning(currentBlockText)))
                    }
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
            swarmProgressStore.setSteps(n)
        }
        if t == "agent", let title = p["title"], let detail = p["detail"] {
            if detail == "started" {
                swarmProgressStore.markStarted(name: title)
            } else if detail == "completed" {
                swarmProgressStore.markCompleted(name: title)
            }
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
        recordTaskActivity(type: t, payload: p, providerId: pid, conversationId: convId)
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
