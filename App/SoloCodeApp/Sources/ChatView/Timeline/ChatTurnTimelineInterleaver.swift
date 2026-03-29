import Foundation

// MARK: - Timeline Interleaver

enum ChatTurnTimelineInterleaver {
    static func segments(
        blocks: [PersistedChatTimelineBlock],
        traceEvents: [ToolTraceEvent],
        liveSubagentCards: [SwarmLiveCardState] = [],
        subagentSnapshots: [SubagentCardSnapshot] = [],
        suppressReasoningBlocks: Bool = false,
        debugAssistantMessageId: UUID? = nil,
        debugConversationId: UUID? = nil
    ) -> [ChatTurnInterleavedSegment] {
        var segments: [ChatTurnInterleavedSegment] = []

        let collapsedTraceEvents = ToolTraceEventCollapser.collapseSupersededToolStates(traceEvents)
        let visibleLiveCards = liveSubagentCards.filter {
            isVisibleSubagentId(normalizedSubagentId($0.swarmId))
        }
        let runningLiveCards = visibleLiveCards.filter { $0.status == .running }

        for block in blocks {
            switch block.kind {
            case .primaryText:
                let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                // Usa sempre `block.sequence` così testo e tool seguono la timeline
                // del bridge/Rust. L’euristica "monolitico" (maxToolSequence+1) metteva
                // tutte le card tool sopra e un unico blocco risposta sotto.
                segments.append(.text(id: block.id, content: block.text, sequence: block.sequence))
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

        for (index, card) in runningLiveCards.enumerated() {
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

        if let completedGroup = completedSubagentGroup(
            traceEvents: traceEvents,
            liveSubagentCards: visibleLiveCards,
            subagentSnapshots: subagentSnapshots,
            fallbackBase: baseSequence + runningLiveCards.count
        ) {
            segments.append(
                .completedSubagentsGroup(
                    id: completedGroup.id,
                    group: completedGroup,
                    sequence: completedGroup.sequence
                )
            )
        }

        let merged = segments
            .sorted { compareSegmentsForTimeline($0, $1) }
            .collapsedConsecutiveToolEvents()

        // #region agent log
        ChatTurnTimelineInterleaverDebug72.logIfMonolithicNoMarkersCase(
            blocks: blocks,
            collapsedTraceCount: collapsedTraceEvents.count,
            merged: merged,
            assistantMessageId: debugAssistantMessageId,
            conversationId: debugConversationId
        )
        // #endregion

        return merged
    }

    /// Ordine con `sequence` identica: non dipendere dal solo `id` (UUID), altrimenti
    /// reasoning e primary possono invertirsi tra run e confondere la UX (log H26 `0R,0T`).
    private static func compareSegmentsForTimeline(
        _ lhs: ChatTurnInterleavedSegment,
        _ rhs: ChatTurnInterleavedSegment
    ) -> Bool {
        if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
        let lp = segmentSequenceTiePriority(lhs)
        let rp = segmentSequenceTiePriority(rhs)
        if lp != rp { return lp < rp }
        return lhs.id < rhs.id
    }

    /// Valori più bassi = più in alto nella colonna.
    private static func segmentSequenceTiePriority(_ segment: ChatTurnInterleavedSegment) -> Int {
        switch segment {
        case .reasoning: return 0
        case .text: return 1
        case .toolEvent, .toolGroup: return 2
        case .subagentLiveCard: return 3
        case .completedSubagentsGroup: return 4
        case .subagentSnapshot: return 5
        case .artifact: return 6
        }
    }

    static func sequenceForSubagentCard(
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

// #region agent log
/// NDJSON mirror sessione Cursor `72ead1` (ordine timeline monolitico vs tool).
private enum ChatTurnTimelineInterleaverDebug72 {
    private static let logPath = "/Users/benjaminstoica/SoloCode/.cursor/debug-72ead1.log"
    private static let monoLogLock = NSLock()
    private static var lastMonoLogAt: CFAbsoluteTime = 0

    static func logIfMonolithicNoMarkersCase(
        blocks: [PersistedChatTimelineBlock],
        collapsedTraceCount: Int,
        merged: [ChatTurnInterleavedSegment],
        assistantMessageId: UUID? = nil,
        conversationId: UUID? = nil
    ) {
        let toolMarkers = blocks.filter { $0.kind == .toolMarker }.count
        let textBlocks = blocks.filter { $0.kind == .primaryText && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard textBlocks.count == 1,
              textBlocks[0].sequence == 0,
              toolMarkers == 0,
              collapsedTraceCount > 0
        else { return }

        monoLogLock.lock()
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastMonoLogAt > 0.55 else {
            monoLogLock.unlock()
            return
        }
        lastMonoLogAt = now
        monoLogLock.unlock()

        let preview = merged.prefix(12).map(_debugInterleavedTag).joined(separator: ",")
        let firstTextSeq = merged.first(where: {
            if case .text = $0 { return true }
            return false
        })?.sequence ?? -1
        var fields: [String: String] = [
            "firstTextSeq": "\(firstTextSeq)",
            "preview": preview,
            "traceCount": "\(collapsedTraceCount)",
        ]
        if let assistantMessageId {
            fields["assistantMessageId"] = assistantMessageId.uuidString.lowercased()
        }
        if let conversationId {
            fields["conversationId"] = conversationId.uuidString.lowercased()
        }
        let payload: [String: Any] = [
            "sessionId": "72ead1",
            "runId": "interleaver-fix11",
            "hypothesisId": "H26",
            "location": "ChatTurnTimelineInterleaver.swift:segments",
            "message": "monolithic_no_markers_merged_order",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "data": fields,
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: json, encoding: .utf8)
        else { return }
        line.append("\n")
        let ndjsonLine = Data(line.utf8)
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: ndjsonLine)
        } else if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            h.write(ndjsonLine)
        }
    }

    private static func _debugInterleavedTag(_ s: ChatTurnInterleavedSegment) -> String {
        let tag: String
        switch s {
        case .text: tag = "T"
        case .reasoning: tag = "R"
        case .toolEvent: tag = "E"
        case .toolGroup: tag = "G"
        case .subagentLiveCard: tag = "L"
        case .completedSubagentsGroup: tag = "C"
        case .subagentSnapshot: tag = "S"
        case .artifact: tag = "A"
        }
        return "\(s.sequence)\(tag)"
    }
}

// #endregion

// MARK: - Consecutive Tool Event Collapsing

extension Array where Element == ChatTurnInterleavedSegment {
    func collapsedConsecutiveToolEvents() -> [ChatTurnInterleavedSegment] {
        var result: [ChatTurnInterleavedSegment] = []
        var index = 0

        while index < count {
            guard case .toolEvent(_, let event, _) = self[index],
                  let category = ChatTurnView.toolGroupCategory(for: event),
                  ChatTurnInlineToolGroupingPolicy.shouldCollapse(category: category) else {
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
