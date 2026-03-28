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
            } else {
                let pNorm = pipelinePrimary.trimmingCharacters(in: .whitespacesAndNewlines)
                let rNorm = merged.resolvedPrimaryText.trimmingCharacters(in: .whitespacesAndNewlines)
                let vNorm = streamingVisiblePrimaryBlockNorm(merged)
                if !pNorm.isEmpty, pNorm != rNorm || pNorm != vNorm {
                    applyLivePrimaryStreamText(&merged, text: pipelinePrimary)
                }
            }
        }

        if streaming.pendingStreamConversationId == convId,
           let pending = streaming.pendingStreamContent,
           !pending.isEmpty
        {
            let trimmed = pending.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let rNorm = merged.resolvedPrimaryText.trimmingCharacters(in: .whitespacesAndNewlines)
                let vNorm = streamingVisiblePrimaryBlockNorm(merged)
                if trimmed != rNorm || trimmed != vNorm || (rNorm.isEmpty && !trimmed.isEmpty) {
                    applyLivePrimaryStreamText(&merged, text: pending)
                }
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

/// Testo del primo blocco `.primaryText` se presente; altrimenti `resolvedPrimaryText` (trim).
private func streamingVisiblePrimaryBlockNorm(_ message: ChatMessage) -> String {
    if let blocks = message.blocks, !blocks.isEmpty,
       let primary = blocks.first(where: { $0.kind == .primaryText })
    {
        return primary.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return message.resolvedPrimaryText.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Allinea `content` / `primaryTextSnapshot` e, se ci sono blocchi, il testo del blocco primary così
/// `resolvedTimelineBlocks` non resta fermo su payload identico (H11 + H25 senza delta visivo).
private func applyLivePrimaryStreamText(_ merged: inout ChatMessage, text: String) {
    merged.content = text
    merged.primaryTextSnapshot = text
    guard var blocks = merged.blocks, !blocks.isEmpty else { return }
    guard let idx = blocks.firstIndex(where: { $0.kind == .primaryText }) else { return }
    blocks[idx].text = text
    merged.blocks = blocks
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
