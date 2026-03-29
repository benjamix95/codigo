import Foundation

extension ChatTurnTimelineInterleaver {
    struct CompletedSubagentCandidate {
        let snapshot: SubagentCardSnapshot
        let liveCard: SwarmLiveCardState?
        let sequence: Int
    }

    private static let completedSubagentLaunchGapThreshold = 1

    static func completedSubagentGroups(
        traceEvents: [ToolTraceEvent],
        blocks: [PersistedChatTimelineBlock],
        liveSubagentCards: [SwarmLiveCardState],
        subagentSnapshots: [SubagentCardSnapshot],
        fallbackBase: Int
    ) -> [ChatTurnCompletedSubagentsGroup] {
        var orderedIds: [String] = []
        var candidates: [String: CompletedSubagentCandidate] = [:]
        let liveIds = Set(
            liveSubagentCards
                .map { normalizedSubagentId($0.swarmId) }
        )

        func upsert(
            snapshot: SubagentCardSnapshot,
            liveCard: SwarmLiveCardState?,
            forceOverride: Bool
        ) {
            let normalizedId = normalizedSubagentId(snapshot.swarmId)
            guard isVisibleSubagentId(normalizedId) else { return }
            let next = CompletedSubagentCandidate(
                snapshot: snapshot,
                liveCard: liveCard,
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

        for snapshot in subagentSnapshots where !liveIds.contains(normalizedSubagentId(snapshot.swarmId)) {
            upsert(snapshot: snapshot, liveCard: nil, forceOverride: false)
        }
        for card in liveSubagentCards {
            upsert(
                snapshot: SubagentCardSnapshot(from: card),
                liveCard: card,
                forceOverride: true
            )
        }

        let orderedCandidates = orderedIds.compactMap { candidates[$0] }
            .sorted {
                if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
                return normalizedSubagentId($0.snapshot.swarmId) < normalizedSubagentId($1.snapshot.swarmId)
            }

        guard !orderedCandidates.isEmpty else { return [] }

        let cohorts = splitCompletedSubagentCandidatesIntoLaunchCohorts(
            orderedCandidates,
            blocks: blocks
        )
        return cohorts.enumerated().compactMap { index, cohort in
            guard let first = cohort.first else { return nil }
            return ChatTurnCompletedSubagentsGroup(
                id: "completed-subagents-\(first.sequence)-\(index)",
                entries: cohort.map {
                    ChatTurnCompletedSubagentsGroupEntry(
                        snapshot: $0.snapshot,
                        liveCard: $0.liveCard
                    )
                },
                sequence: first.sequence
            )
        }
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

    private static func splitCompletedSubagentCandidatesIntoLaunchCohorts(
        _ candidates: [CompletedSubagentCandidate],
        blocks: [PersistedChatTimelineBlock]
    ) -> [[CompletedSubagentCandidate]] {
        guard !candidates.isEmpty else { return [] }

        var cohorts: [[CompletedSubagentCandidate]] = []
        var currentCohort: [CompletedSubagentCandidate] = [candidates[0]]

        for candidate in candidates.dropFirst() {
            guard let previous = currentCohort.last else {
                currentCohort = [candidate]
                continue
            }

            if shouldStartNewCompletedSubagentCohort(
                previous: previous,
                next: candidate,
                blocks: blocks
            ) {
                cohorts.append(currentCohort)
                currentCohort = [candidate]
            } else {
                currentCohort.append(candidate)
            }
        }

        if !currentCohort.isEmpty {
            cohorts.append(currentCohort)
        }
        return cohorts
    }

    private static func shouldStartNewCompletedSubagentCohort(
        previous: CompletedSubagentCandidate,
        next: CompletedSubagentCandidate,
        blocks: [PersistedChatTimelineBlock]
    ) -> Bool {
        let gap = next.sequence - previous.sequence
        if gap > completedSubagentLaunchGapThreshold {
            return true
        }

        return blocks.contains { block in
            guard block.sequence > previous.sequence, block.sequence < next.sequence else {
                return false
            }
            switch block.kind {
            case .primaryText, .files, .commands, .toolTrace, .status, .plan, .mermaid:
                return true
            case .reasoning, .toolMarker:
                return false
            }
        }
    }
}
