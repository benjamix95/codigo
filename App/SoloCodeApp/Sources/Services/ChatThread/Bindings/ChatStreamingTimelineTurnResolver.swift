import CoderEngine
import Foundation

enum ChatStreamingTimelineTurnSource: Equatable {
    case integrationRuntime
    case conversationRuntime
    case assistantMessageCache
    case persistedMessage
    case synthetic
    case none
}

struct ChatStreamingTimelineTurnResolution: Equatable {
    let turn: ChatTurnState?
    let source: ChatStreamingTimelineTurnSource
    let syntheticReason: String?

    var usedSynthetic: Bool { source == .synthetic }
}

enum ChatStreamingTimelineTurnResolver {
    static func resolve(
        base: ChatMessage,
        conversationId: UUID,
        integrationTurn: ChatTurnState?,
        conversationTurn: ChatTurnState?,
        cachedAssistantTurn: ChatTurnState?,
        persistedMessage: ChatMessage?,
        traceEvents: [ToolTraceEvent]
    ) -> ChatStreamingTimelineTurnResolution {
        let bestRealTurn = bestMatchingRealTurn(
            base: base,
            conversationId: conversationId,
            integrationTurn: integrationTurn,
            conversationTurn: conversationTurn,
            cachedAssistantTurn: cachedAssistantTurn,
            persistedMessage: persistedMessage
        )

        if let synthetic = SyntheticChatTurnStateFromTraceEvents.makeForMergeIfNeeded(
            base: base,
            conversationId: conversationId,
            traceEvents: traceEvents
        ) {
            let realToolMarkers = bestRealTurn?.turn.blocks.filter { $0.kind == .toolMarker }.count ?? 0
            if bestRealTurn == nil {
                return ChatStreamingTimelineTurnResolution(
                    turn: synthetic,
                    source: .synthetic,
                    syntheticReason: "no_pipeline_turn"
                )
            }
            if realToolMarkers == 0, !traceEvents.isEmpty {
                return ChatStreamingTimelineTurnResolution(
                    turn: synthetic,
                    source: .synthetic,
                    syntheticReason: "pipeline_zero_tool_markers"
                )
            }
        }

        guard let bestRealTurn else {
            return ChatStreamingTimelineTurnResolution(
                turn: nil,
                source: .none,
                syntheticReason: nil
            )
        }

        return ChatStreamingTimelineTurnResolution(
            turn: bestRealTurn.turn,
            source: bestRealTurn.source,
            syntheticReason: nil
        )
    }

    private static func bestMatchingRealTurn(
        base: ChatMessage,
        conversationId: UUID,
        integrationTurn: ChatTurnState?,
        conversationTurn: ChatTurnState?,
        cachedAssistantTurn: ChatTurnState?,
        persistedMessage: ChatMessage?
    ) -> (turn: ChatTurnState, source: ChatStreamingTimelineTurnSource)? {
        var candidates: [(turn: ChatTurnState, source: ChatStreamingTimelineTurnSource)] = []

        appendCandidate(
            turn: integrationTurn,
            source: .integrationRuntime,
            base: base,
            to: &candidates
        )
        appendCandidate(
            turn: conversationTurn,
            source: .conversationRuntime,
            base: base,
            to: &candidates
        )
        appendCandidate(
            turn: cachedAssistantTurn,
            source: .assistantMessageCache,
            base: base,
            to: &candidates
        )

        if let persistedMessage,
           persistedMessage.id == base.id,
           shouldPreferPipelineTimelineBlocks(
               localBlocks: base.resolvedTimelineBlocks,
               pipelineBlocks: persistedMessage.resolvedTimelineBlocks
           )
        {
            candidates.append(
                (
                    restoredChatTurnStateFromPersistedAssistantMessage(
                        conversationId: conversationId,
                        message: persistedMessage
                    ),
                    .persistedMessage
                )
            )
        }

        var best: (turn: ChatTurnState, source: ChatStreamingTimelineTurnSource)?
        for candidate in candidates {
            guard let currentBest = best else {
                best = candidate
                continue
            }
            if shouldPreferCandidateTurn(candidate.turn, over: currentBest.turn) {
                best = candidate
            }
        }
        return best
    }

    private static func appendCandidate(
        turn: ChatTurnState?,
        source: ChatStreamingTimelineTurnSource,
        base: ChatMessage,
        to candidates: inout [(turn: ChatTurnState, source: ChatStreamingTimelineTurnSource)]
    ) {
        guard let turn, turn.assistantMessageId == base.id else { return }
        candidates.append((turn, source))
    }

    private static func shouldPreferCandidateTurn(
        _ candidate: ChatTurnState,
        over current: ChatTurnState
    ) -> Bool {
        if shouldPreferPipelineTimelineBlocks(
            localBlocks: current.blocks,
            pipelineBlocks: candidate.blocks
        ) {
            return true
        }
        if candidate.timelineSegments.count > current.timelineSegments.count {
            return true
        }
        if candidate.textSegments.count > current.textSegments.count {
            return true
        }
        return candidate.timelineNextSequence > current.timelineNextSequence
    }
}
