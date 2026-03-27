import CoderEngine
import Foundation
import SwiftUI

extension ChatPanelView {
    /// Allinea la timeline del messaggio assistente in streaming a sorgenti **più fresche** dello
    /// snapshot/hop store quando `streamContentVersion` avanza senza mutare `messagesConversationSnapshot`
    /// (log H11): buffer throttle `pendingStreamContent` e `PipelineConversationRuntime.chatTurnState` tra
    /// round-trip Rust/debounce.
    internal func messageForStreamingTimelineDisplay(
        base: ChatMessage,
        conversationId convId: UUID
    ) -> ChatMessage {
        guard base.role == .assistant,
              base.isStreaming,
              snapshotIsLoading,
              let activeId = snapshotActiveAssistantMessageId,
              base.id == activeId
        else { return base }

        var merged = base
        let storePayload = streamingTimelinePayloadCharSum(merged)

        if let runtime = pipelineIntegrationService.runtime(for: convId),
           runtime.assistantMessageId == base.id
        {
            let turn = runtime.chatTurnState
            let pipelineBlocks = turn.blocks
            let pipelinePayload = streamingTimelinePayloadCharSum(forBlocks: pipelineBlocks)
            let pipelinePrimary = turn.primaryTextSnapshot
            if pipelinePayload > storePayload, !pipelineBlocks.isEmpty {
                merged.blocks = pipelineBlocks
                merged.primaryTextSnapshot = pipelinePrimary
                if merged.content.count < pipelinePrimary.count {
                    merged.content = pipelinePrimary
                }
            } else if pipelinePrimary.count > merged.resolvedPrimaryText.count {
                merged.primaryTextSnapshot = pipelinePrimary
                merged.content = pipelinePrimary
            }
        }

        if streaming.pendingStreamConversationId == convId,
           let pending = streaming.pendingStreamContent,
           !pending.isEmpty
        {
            let trimmed = pending.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > merged.resolvedPrimaryText.count
                || (merged.resolvedPrimaryText.isEmpty && !trimmed.isEmpty)
            {
                merged.content = pending
                merged.primaryTextSnapshot = pending
            }
        }

        let mergedPayload = streamingTimelinePayloadCharSum(merged)
        let blocksChanged = merged.blocks != base.blocks
        let materialMerge =
            mergedPayload != storePayload
            || merged.content != base.content
            || blocksChanged
            || (merged.primaryTextSnapshot ?? "") != (base.primaryTextSnapshot ?? "")
        if materialMerge {
            // #region agent log
            AgentDebugSessionNDJSONLog.appendThrottled(
                gateKey: "H25-stream-display-merge",
                minInterval: 0.07,
                hypothesisId: "H25",
                location: "messageForStreamingTimelineDisplay",
                message: "streaming_timeline_merged_ahead_of_store",
                data: [
                    "conversationId": convId.uuidString,
                    "messageId": base.id.uuidString,
                    "storePayload": "\(storePayload)",
                    "mergedPayload": "\(mergedPayload)",
                    "streamContentVersion": "\(streaming.streamContentVersion)",
                    "hadPending": "\(streaming.pendingStreamConversationId == convId && streaming.pendingStreamContent != nil)",
                ]
            )
            // #endregion
        }

        return merged
    }
}

private func streamingTimelinePayloadCharSum(_ message: ChatMessage) -> Int {
    message.resolvedTimelineBlocks.reduce(0) { partial, block in
        partial + block.text.count + block.items.reduce(0) { $0 + $1.count }
    }
}

private func streamingTimelinePayloadCharSum(forBlocks blocks: [PersistedChatTimelineBlock]) -> Int {
    blocks.reduce(0) { partial, block in
        partial + block.text.count + block.items.reduce(0) { $0 + $1.count }
    }
}
