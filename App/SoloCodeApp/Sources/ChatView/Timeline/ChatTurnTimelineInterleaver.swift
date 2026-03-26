import Foundation

// MARK: - Timeline Interleaver

enum ChatTurnTimelineInterleaver {
    static func segments(
        blocks: [PersistedChatTimelineBlock],
        traceEvents: [ToolTraceEvent],
        liveSubagentCards: [SwarmLiveCardState] = [],
        subagentSnapshots: [SubagentCardSnapshot] = [],
        suppressReasoningBlocks: Bool = false
    ) -> [ChatTurnInterleavedSegment] {
        var segments: [ChatTurnInterleavedSegment] = []

        // Collect toolMarker sequences from Rust pipeline.
        // These mark where tool invocations occurred in the text stream.
        let toolMarkerSequences = blocks
            .filter { $0.kind == .toolMarker }
            .map(\.sequence)
            .sorted()

        let collapsedTraceEvents = ToolTraceEventCollapser.collapseSupersededToolStates(traceEvents)

        // Detect the "single monolithic text block" case:
        // one primaryText at sequence 0, no other text blocks, and tool events exist.
        let textBlocks = blocks.filter { $0.kind == .primaryText && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let hasToolEvents = !collapsedTraceEvents.isEmpty
        let isSingleMonolithicText = textBlocks.count == 1
            && textBlocks[0].sequence == 0
            && hasToolEvents
            && toolMarkerSequences.isEmpty

        let maxToolSequence = collapsedTraceEvents.map(\.sequence).max() ?? 0

        for block in blocks {
            switch block.kind {
            case .primaryText:
                let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                // When we have a single text block at sequence 0 and tool events
                // exist but no toolMarkers (pipeline didn't track tool segments),
                // place text AFTER the last tool event. This is the common case:
                // LLM uses tools then writes a summary/response.
                let effectiveSequence: Int
                if isSingleMonolithicText {
                    effectiveSequence = maxToolSequence + 1
                } else {
                    effectiveSequence = block.sequence
                }
                segments.append(.text(id: block.id, content: block.text, sequence: effectiveSequence))
            case .reasoning:
                if suppressReasoningBlocks { continue }
                segments.append(.reasoning(id: block.id, text: block.text, sequence: block.sequence))
            case .toolMarker:
                // toolMarkers are placeholders from Rust — their sequence is used
                // by the sorted output to position tool events relative to text.
                // We don't render them directly; tool events from ToolTraceStore
                // carry their own sequences that align with these markers.
                continue
            default:
                segments.append(.artifact(id: block.id, block: block, sequence: block.sequence))
            }
        }

        for event in collapsedTraceEvents {
            segments.append(
                .toolEvent(
                    id: event.id.uuidString.lowercased(),
                    event: event,
                    sequence: event.sequence
                )
            )
        }

        let baseSequence = max(
            blocks.map(\.sequence).max() ?? 0,
            traceEvents.map(\.sequence).max() ?? 0
        )

        for (index, card) in liveSubagentCards.enumerated() {
            segments.append(
                .subagentLiveCard(
                    id: card.swarmId.lowercased(),
                    card: card,
                    sequence: sequenceForSubagentCard(
                        swarmId: card.swarmId,
                        traceEvents: traceEvents,
                        fallbackBase: baseSequence,
                        offset: index
                    )
                )
            )
        }

        for (index, snapshot) in subagentSnapshots.enumerated() {
            segments.append(
                .subagentSnapshot(
                    id: snapshot.swarmId.lowercased(),
                    snapshot: snapshot,
                    sequence: sequenceForSubagentCard(
                        swarmId: snapshot.swarmId,
                        traceEvents: traceEvents,
                        fallbackBase: baseSequence + liveSubagentCards.count,
                        offset: index
                    )
                )
            )
        }

        return segments.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            return lhs.id < rhs.id
        }
        .collapsedConsecutiveToolEvents()
    }

    private static func sequenceForSubagentCard(
        swarmId: String,
        traceEvents: [ToolTraceEvent],
        fallbackBase: Int,
        offset: Int
    ) -> Int {
        let normalizedSwarmId = swarmId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let earliestMatch = traceEvents
            .filter({
                ($0.payload["swarm_id"] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == normalizedSwarmId
            })
            .map(\.sequence)
            .min() {
            return earliestMatch
        }
        return fallbackBase + offset + 1
    }
}

// MARK: - Consecutive Tool Event Collapsing

extension Array where Element == ChatTurnInterleavedSegment {
    func collapsedConsecutiveToolEvents() -> [ChatTurnInterleavedSegment] {
        var result: [ChatTurnInterleavedSegment] = []
        var index = 0

        while index < count {
            guard case .toolEvent(_, let event, _) = self[index],
                  let category = ChatTurnView.toolGroupCategory(for: event) else {
                result.append(self[index])
                index += 1
                continue
            }

            var groupedEvents: [ToolTraceEvent] = [event]
            var lookahead = index + 1
            while lookahead < count {
                guard case .toolEvent(_, let nextEvent, _) = self[lookahead],
                      ChatTurnView.toolGroupCategory(for: nextEvent) == category else {
                    break
                }
                groupedEvents.append(nextEvent)
                lookahead += 1
            }

            if groupedEvents.count > 1 {
                let firstEvent = groupedEvents[0]
                let group = ChatTurnToolEventGroup(
                    id: "\(category.rawValue)-\(firstEvent.id.uuidString.lowercased())",
                    category: category,
                    events: groupedEvents,
                    sequence: firstEvent.sequence
                )
                result.append(.toolGroup(id: group.id, group: group, sequence: group.sequence))
            } else {
                result.append(self[index])
            }
            index = lookahead
        }

        return result
    }
}
