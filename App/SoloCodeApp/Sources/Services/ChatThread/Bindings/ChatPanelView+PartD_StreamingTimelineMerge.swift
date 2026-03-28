import CoderEngine
import Foundation
import SwiftUI

extension ChatPanelView {
    /// Allinea la timeline del messaggio assistente in streaming a sorgenti **più fresche** dello
    /// snapshot/hop store quando `streamContentVersion` avanza senza mutare `messagesConversationSnapshot`
    /// (log H11): buffer throttle `pendingStreamContent` e, in ordine, `PipelineConversationRuntime.chatTurnState`
    /// oppure `conversationRuntime.activeTurnStateByConversation` (trace tool / Swift-only pipeline).
    internal func messageForStreamingTimelineDisplay(
        base: ChatMessage,
        conversationId convId: UUID
    ) -> ChatMessage {
        guard base.role == .assistant else { return base }

        /// Gate solo per il buffer `pendingStreamContent` (H11). Blocchi/toolMarker da `chatTurnState`
        /// devono fondersi anche se il messaggio non è più la sola superficie “streaming attivo”
        /// (history vs split stack, `snapshotIsLoading` falso, ecc.) — altrimenti H26 con molti trace.
        let isActiveStreamingSurface =
            base.isStreaming
            && snapshotIsLoading
            && snapshotActiveAssistantMessageId == base.id

        var merged = base
        let storePayload = streamingTimelinePayloadCharSum(merged)

        /// `appendToolTraceEvent` aggiorna `conversationRuntime`; il merge leggeva **solo**
        /// `pipelineIntegrationService.runtime`, spesso `nil` (nessun job / teardown) → H34 senza H35 e H26.
        let chatTurnForMerge: ChatTurnState? = {
            let integration = pipelineIntegrationService.runtime(for: convId)
            if let r = integration, r.assistantMessageId == base.id {
                return r.chatTurnState
            }
            if let s = conversationRuntime.activeTurnStateByConversation[convId],
               s.assistantMessageId == base.id {
                return s
            }
            if let cached = conversationRuntime.pipelineTurnStateByAssistantMessageId[base.id] {
                // #region agent log
                StreamingTimelineMergeDebug72.logMergeUsesAssistantMessagePipelineCache(
                    conversationId: convId,
                    messageId: base.id,
                    pipeMarkers: cached.blocks.filter { $0.kind == .toolMarker }.count
                )
                // #endregion
                return cached
            }
            return nil
        }()

        if let turn = chatTurnForMerge {
            let usedConversationOnly = pipelineIntegrationService.runtime(for: convId)
                .map { $0.assistantMessageId != base.id } ?? true
                && conversationRuntime.activeTurnStateByConversation[convId]?.assistantMessageId == base.id
            if usedConversationOnly {
                // #region agent log
                StreamingTimelineMergeDebug72.logMergeUsesConversationRuntime(
                    conversationId: convId,
                    messageId: base.id,
                    pipeMarkers: turn.blocks.filter { $0.kind == .toolMarker }.count
                )
                // #endregion
            }
            let pipelineBlocks = turn.blocks
            let pipelinePayload = streamingTimelinePayloadCharSum(forBlocks: pipelineBlocks)
            let pipelinePrimary = turn.primaryTextSnapshot
            let baseBlocks = base.blocks ?? []
            let baseToolMarkers = baseBlocks.filter { $0.kind == .toolMarker }.count
            let pipeToolMarkers = pipelineBlocks.filter { $0.kind == .toolMarker }.count
            let structureAhead = streamingPipelineHasRicherBlockStructure(
                baseBlocks: baseBlocks,
                pipelineBlocks: pipelineBlocks
            )
            let payloadAhead = pipelinePayload > storePayload && !pipelineBlocks.isEmpty

            if structureAhead || payloadAhead {
                // `ChatTurnTimelineInterleaver`: senza toolMarker ma con trace, un solo primaryText(0)
                // diventa “monolitico”. I marker non contribuiscono a `pipelinePayload` (text vuoto):
                // senza `structureAhead` il merge non partiva mai se lo store aveva già tutto il testo (H26).
                if pipeToolMarkers < baseToolMarkers {
                    let trimmedPrimary = pipelinePrimary.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedPrimary.isEmpty {
                        applyLivePrimaryStreamText(&merged, text: pipelinePrimary)
                    }
                } else {
                    if structureAhead, !payloadAhead {
                        // #region agent log
                        StreamingTimelineMergeDebug72.logStructureWithoutPayloadDelta(
                            baseToolMarkers: baseToolMarkers,
                            pipeToolMarkers: pipeToolMarkers,
                            storePayload: storePayload,
                            pipelinePayload: pipelinePayload
                        )
                        // #endregion
                    }
                    if !isActiveStreamingSurface, pipeToolMarkers > 0 {
                        // #region agent log
                        StreamingTimelineMergeDebug72.logBlocksMergedOutsideActiveSurface(
                            messageId: base.id,
                            pipeToolMarkers: pipeToolMarkers
                        )
                        // #endregion
                    }
                    merged.blocks = pipelineBlocks
                    merged.primaryTextSnapshot = pipelinePrimary
                    if merged.content.count < pipelinePrimary.count {
                        merged.content = pipelinePrimary
                    }
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

        if isActiveStreamingSurface,
           streaming.pendingStreamConversationId == convId,
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

/// Più marker `.toolUse` / segmenti timeline rispetto al messaggio store, anche senza aumento caratteri.
private func streamingPipelineHasRicherBlockStructure(
    baseBlocks: [PersistedChatTimelineBlock],
    pipelineBlocks: [PersistedChatTimelineBlock]
) -> Bool {
    guard !pipelineBlocks.isEmpty else { return false }
    let baseMarkers = baseBlocks.filter { $0.kind == .toolMarker }.count
    let pipeMarkers = pipelineBlocks.filter { $0.kind == .toolMarker }.count
    if pipeMarkers > baseMarkers { return true }
    if pipelineBlocks.count > baseBlocks.count { return true }
    return false
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
