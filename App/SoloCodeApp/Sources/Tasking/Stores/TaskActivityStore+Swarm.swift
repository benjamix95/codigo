import Foundation

@MainActor
extension TaskActivityStore {
    private func sortedSwarmCardsSnapshot() -> [SwarmLiveCardState] {
        SwarmLiveReducer.sorted(states: Array(swarmCards.values))
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
        let owner = SwarmLiveReducer.ownerSwarmId(for: activity, includeOrchestratorFallback: false)
        if owner == "orchestrator" {
            swarmEventsFallbackCount += 1
        } else if let o = owner {
            swarmEventsAssignedCount += 1
            swarmLogger.debug(
                "Swarm event assigned to subagent '\(o)' type=\(activity.type) stage=\(activity.payload["subagent_stage"] ?? "-") title=\(activity.title) detail=\(activity.detail ?? "-")"
            )
        } else if SwarmMetadata.isSupervisorEvent(activity.payload) {
            swarmEventsFallbackCount += 1
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
        scopedSwarmCardsCache.removeAll()
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
        scopedSwarmCardsCache.removeAll(keepingCapacity: true)
    }

    func refreshSortedSwarmCardsCacheIfNeeded() {
        guard isSortedSwarmCardsCacheDirty else { return }
        sortedSwarmCardsCache = sortedSwarmCardsSnapshot()
        isSortedSwarmCardsCacheDirty = false
    }

    func currentSortedSwarmCardsSnapshot() -> [SwarmLiveCardState] {
        if isSortedSwarmCardsCacheDirty {
            return sortedSwarmCardsSnapshot()
        }
        return sortedSwarmCardsCache
    }
}
