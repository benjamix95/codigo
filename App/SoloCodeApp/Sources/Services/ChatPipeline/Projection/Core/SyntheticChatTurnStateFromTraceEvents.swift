import Foundation

/// Quando il persistito non ha `toolMarker` ma `ToolTraceStore` ha trace per quel `assistantMessageId`
/// (es. mismatch id risolto solo in avanti, o commit pipeline mai arrivato), il merge non trova `ChatTurnState` → H26.
enum SyntheticChatTurnStateFromTraceEvents {
    /// Timeline minimale: un `.text` a sequence 0 (se c’è testo visibile) e un `.toolUse` per ogni trace
    /// collassato, con sequence allineata a `ToolTraceEvent.sequence` (o ≥1 se serve evitare collisione con il testo).
    static func makeForMergeIfNeeded(
        base: ChatMessage,
        conversationId: UUID,
        traceEvents: [ToolTraceEvent]
    ) -> ChatTurnState? {
        guard base.role == .assistant else { return nil }
        let baseMarkers = (base.blocks ?? []).filter { $0.kind == .toolMarker }.count
        guard baseMarkers == 0 else { return nil }

        let collapsed = ToolTraceEventCollapser.collapseSupersededToolStates(traceEvents)
        guard !collapsed.isEmpty else { return nil }

        let turnId = base.turnMetadata?.turnId ?? base.id.uuidString
        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: base.id,
            turnId: turnId,
            providerId: base.turnMetadata?.providerId
        )
        state.isStreaming = base.isStreaming
        state.status = base.turnMetadata?.status ?? (base.isStreaming ? "streaming" : "idle")
        state.sequence = base.turnMetadata?.sequence ?? 0
        state.updatedAt = base.turnMetadata?.updatedAt

        let visibleBlocks = base.resolvedTimelineBlocks.filter { $0.kind != .toolMarker }
        let primaryBlocks = visibleBlocks.filter { $0.kind == .primaryText }
        let primaryTexts = primaryBlocks.map(\.text)
        let primaryText = primaryTexts
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPrimary = !primaryText.isEmpty
        struct TimelineSeed {
            let sequence: Int
            let kindPriority: Int
            let order: Int
            let segment: ChatTimelineSegment
        }
        var timelineSeeds: [TimelineSeed] = []
        if hasPrimary {
            state.textSegments = primaryTexts
            state.textByStreamId["main"] = primaryText
            state.orderedTextStreamIds = ["main"]
            timelineSeeds.append(contentsOf: primaryBlocks.enumerated().map { index, block in
                TimelineSeed(
                    sequence: block.sequence,
                    kindPriority: 1,
                    order: index,
                    segment: ChatTimelineSegment(kind: .text, index: index, sequence: block.sequence)
                )
            })
        } else {
            state.textSegments = []
            state.orderedTextStreamIds = []
        }

        let sorted = collapsed.sorted {
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.timestamp < $1.timestamp
        }
        timelineSeeds.append(contentsOf: sorted.enumerated().map { index, ev in
            let seq = hasPrimary && ev.sequence == 0 ? 1 : ev.sequence
            return TimelineSeed(
                sequence: seq,
                kindPriority: 2,
                order: index,
                segment: ChatTimelineSegment(kind: .toolUse, index: 0, sequence: seq)
            )
        })

        let reasoningBlocks = visibleBlocks.filter { $0.kind == .reasoning }
        let reasoningText = reasoningBlocks
            .map(\.text)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !reasoningText.isEmpty {
            state.reasoningByGroupId["reasoning"] = reasoningText
            let reasoningSequence = reasoningBlocks.map(\.sequence).min()
                ?? timelineSeeds.map(\.sequence).min()
                ?? 0
            timelineSeeds.append(
                TimelineSeed(
                    sequence: reasoningSequence,
                    kindPriority: 0,
                    order: 0,
                    segment: ChatTimelineSegment(kind: .reasoning, index: 0, sequence: reasoningSequence)
                )
            )
        }

        state.timelineSegments = timelineSeeds
            .sorted {
                if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
                if $0.kindPriority != $1.kindPriority { return $0.kindPriority < $1.kindPriority }
                return $0.order < $1.order
            }
            .map(\.segment)
        let maxSeq = state.timelineSegments.map(\.sequence).max() ?? 0
        state.timelineNextSequence = maxSeq + 1

        return state
    }
}
