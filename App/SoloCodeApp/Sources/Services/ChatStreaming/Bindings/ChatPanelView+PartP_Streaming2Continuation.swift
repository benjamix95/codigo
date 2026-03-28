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
            if shouldSplitStreamingAssistantOnRawTurnStarted(
                shouldApplyPipelineArtifacts: shouldApplyPipelineArtifacts,
                shouldUseLinearChat: shouldUseLinearChat(providerId: pid)
            ) {
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
        handleRawStreamEventContinuationSideEffects(
            type: t,
            payload: p,
            providerId: pid,
            conversationId: convId,
            shouldApplyPipelineArtifacts: shouldApplyPipelineArtifacts,
            shouldUpdateInlineReasoningVisuals: shouldUpdateInlineReasoningVisuals
        )
    }
}
