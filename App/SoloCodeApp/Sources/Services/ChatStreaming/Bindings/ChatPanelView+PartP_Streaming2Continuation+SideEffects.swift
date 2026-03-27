import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func handleRawStreamEventContinuationSideEffects(
        type t: String, payload p: [String: String], providerId pid: String,
        conversationId convId: UUID?,
        shouldApplyPipelineArtifacts: Bool,
        shouldUpdateInlineReasoningVisuals: Bool
    ) {
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
            // #region agent log
            RuntimeEvidenceDebugLog.appendThrottled(
                gateKey: "H6-assistant-update-\((convId ?? selectedConversationId)?.uuidString ?? "nil")",
                minInterval: 0.25,
                hypothesisId: "H6",
                location: "handleRawStreamEventContinuationSideEffects",
                message: "assistant_update_kept_internal",
                data: [
                    "conversationId": (convId ?? selectedConversationId)?.uuidString ?? "nil",
                    "providerId": pid,
                    "outputLen": "\(output.count)",
                    "title": String((p["title"] ?? "").prefix(80)),
                    "detail": String((p["detail"] ?? "").prefix(120)),
                    "status": p["status"] ?? "",
                ]
            )
            // #endregion
            if pid == "codex-cli",
               let targetConversationId = convId ?? selectedConversationId,
               let target = currentAssistantPipelineTarget(for: targetConversationId)
            {
                let cleanedOutput = ChatStore.stripCoderideMarkers(output, aggressive: true)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let currentContent = chatStore.conversation(for: targetConversationId)?
                    .messages.first(where: { $0.id == target.messageId })?
                    .content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let isForwardTextSnapshot =
                    !cleanedOutput.isEmpty
                    && cleanedOutput.count > currentContent.count
                    && (currentContent.isEmpty || cleanedOutput.hasPrefix(currentContent))
                if isForwardTextSnapshot {
                    streaming.streamThrottleTask?.cancel()
                    streaming.streamThrottleTask = nil
                    streaming.pendingStreamContent = nil
                    streaming.pendingStreamConversationId = nil
                    streaming.pendingStreamQueuedAt = nil
                    streaming.pendingStreamOverwriteCount = 0
                    // #region agent log
                    RuntimeEvidenceDebugLog.appendThrottled(
                        gateKey: "H34-assistant-update-chat-catchup-\(targetConversationId.uuidString)",
                        minInterval: 0.08,
                        hypothesisId: "H34",
                        location: "handleRawStreamEventContinuationSideEffects",
                        message: "assistant_update_promoted_to_chat_snapshot",
                        data: [
                            "conversationId": targetConversationId.uuidString,
                            "providerId": pid,
                            "messageId": target.messageId.uuidString,
                            "currentLen": "\(currentContent.count)",
                            "outputLen": "\(cleanedOutput.count)",
                        ]
                    )
                    // #endregion
                    applyMainChatUIStreamIntent(
                        "stream_replace_text",
                        conversationId: targetConversationId,
                        providerId: pid,
                        text: cleanedOutput
                    )
                }
            }
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
