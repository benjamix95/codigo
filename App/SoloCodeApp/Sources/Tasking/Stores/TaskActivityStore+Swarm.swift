import Foundation

@MainActor
extension TaskActivityStore {
    private func sortedSwarmCardsSnapshot() -> [SwarmLiveCardState] {
        if isSortedSwarmCardsCacheDirty {
            return SwarmLiveReducer.sorted(states: Array(swarmCards.values))
        }
        return sortedSwarmCardsCache
    }

    func shouldPreserveSwarmCriticalEvent(_ activity: TaskActivity) -> Bool {
        guard SwarmLiveReducer.ownerSwarmId(for: activity, includeOrchestratorFallback: false) != nil
        else {
            return false
        }
        return SwarmLiveReducer.isSwarmCriticalTransition(activity)
    }

    func ingestSwarmCard(activity: TaskActivity) {
        swarmEventsReceivedCount += 1
        let owner = SwarmLiveReducer.ownerSwarmId(for: activity, includeOrchestratorFallback: true)
        if owner == "orchestrator" {
            swarmEventsFallbackCount += 1
        } else if let o = owner {
            swarmEventsAssignedCount += 1
            swarmLogger.debug(
                "Swarm event assigned to subagent '\(o)' type=\(activity.type) stage=\(activity.payload["subagent_stage"] ?? "-") title=\(activity.title) detail=\(activity.detail ?? "-")"
            )
        }
        SwarmLiveReducer.apply(
            activity: activity,
            to: &swarmCards,
            dedupeKeys: &swarmCardDedupKeys,
            limitRecentEvents: defaultSwarmEventsLimit
        )
        markSortedSwarmCardsDirty()
    }

    func rebuildSwarmCards() {
        swarmCards.removeAll()
        swarmCardDedupKeys.removeAll()
        sortedSwarmCardsCache.removeAll()
        isSortedSwarmCardsCacheDirty = false
        swarmEventsReceivedCount = 0
        swarmEventsAssignedCount = 0
        swarmEventsFallbackCount = 0
        for activity in activities {
            ingestSwarmCard(activity: activity)
        }
    }

    func markSortedSwarmCardsDirty() {
        isSortedSwarmCardsCacheDirty = true
    }

    func refreshSortedSwarmCardsCacheIfNeeded() {
        guard isSortedSwarmCardsCacheDirty else { return }
        sortedSwarmCardsCache = sortedSwarmCardsSnapshot()
        isSortedSwarmCardsCacheDirty = false
    }

    func currentSortedSwarmCardsSnapshot() -> [SwarmLiveCardState] {
        sortedSwarmCardsSnapshot()
    }
}
