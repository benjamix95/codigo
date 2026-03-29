import Foundation

extension ChatTurnTimelineInterleaver {
    struct CompletedSubagentCandidate {
        let snapshot: SubagentCardSnapshot
        let sequence: Int
    }

    static func completedSubagentGroup(
        traceEvents: [ToolTraceEvent],
        liveSubagentCards: [SwarmLiveCardState],
        subagentSnapshots: [SubagentCardSnapshot],
        fallbackBase: Int
    ) -> ChatTurnCompletedSubagentsGroup? {
        var orderedIds: [String] = []
        var candidates: [String: CompletedSubagentCandidate] = [:]
        let activeLiveIds = Set(
            liveSubagentCards
                .filter { $0.status == .running }
                .map { normalizedSubagentId($0.swarmId) }
        )

        func upsert(snapshot: SubagentCardSnapshot, forceOverride: Bool) {
            let normalizedId = normalizedSubagentId(snapshot.swarmId)
            guard isVisibleSubagentId(normalizedId), isTerminal(snapshot.status) else { return }
            let next = CompletedSubagentCandidate(
                snapshot: snapshot,
                sequence: sequenceForSubagentCard(
                    swarmId: snapshot.swarmId,
                    traceEvents: traceEvents,
                    fallbackBase: fallbackBase,
                    offset: orderedIds.count
                )
            )
            if candidates[normalizedId] == nil {
                orderedIds.append(normalizedId)
            }
            if forceOverride || candidates[normalizedId] == nil {
                candidates[normalizedId] = next
            }
        }

        for snapshot in subagentSnapshots where !activeLiveIds.contains(normalizedSubagentId(snapshot.swarmId)) {
            upsert(snapshot: snapshot, forceOverride: false)
        }
        for card in liveSubagentCards where isTerminal(card.status) {
            upsert(snapshot: SubagentCardSnapshot(from: card), forceOverride: true)
        }

        let orderedCandidates = orderedIds.compactMap { candidates[$0] }
            .sorted {
                if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
                return normalizedSubagentId($0.snapshot.swarmId) < normalizedSubagentId($1.snapshot.swarmId)
            }

        guard let first = orderedCandidates.first else { return nil }
        return ChatTurnCompletedSubagentsGroup(
            id: "completed-subagents-\(first.sequence)",
            cards: orderedCandidates.map(\.snapshot),
            sequence: first.sequence
        )
    }

    static func isTerminal(_ status: SwarmCardStatus) -> Bool {
        status == .completed || status == .failed
    }

    static func normalizedSubagentId(_ swarmId: String) -> String {
        swarmId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func isVisibleSubagentId(_ swarmId: String) -> Bool {
        !swarmId.isEmpty && swarmId != "orchestrator"
    }
}
