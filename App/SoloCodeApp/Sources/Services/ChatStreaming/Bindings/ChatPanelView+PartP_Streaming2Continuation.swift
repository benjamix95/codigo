import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func handleRawStreamEventContinuation(
        type t: String, payload p: [String: String], providerId pid: String,
        conversationId convId: UUID?,
        shouldApplyPipelineArtifacts: Bool,
        shouldUpdateInlineReasoningVisuals: Bool
    ) {
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
        if t == "reasoning", let output = p["output"], !output.isEmpty {
            if isReasoningSuppressedForProvider(pid) {
                return
            }
            guard shouldUpdateInlineReasoningVisuals else {
                recordTaskActivity(type: t, payload: p, providerId: pid, conversationId: convId)
                return
            }
            let splitThinking = shouldSplitThinkingMessages(providerId: pid)
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
                if shouldUseLinearChat(providerId: pid), shouldUpdateVisibleReasoning {
                    streaming.codexLastReasoningLine = ChatStore.sanitizedChatReasoningText(
                        output.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                guard shouldUpdateVisibleReasoning else {
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
}
