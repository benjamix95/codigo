import CoderEngine
import Foundation

@MainActor
extension TaskActivityStore {
    func isPlanRelevantActivity(_ activity: TaskActivity) -> Bool {
        let registryDriven = Self.registryDrivenVisibleTypes
        let type = activity.type.lowercased()
        if registryDriven.contains(type) { return true }
        switch type {
        case "command_execution", "bash",
             "read_batch_started", "read_batch_completed",
             "web_search", "web_search_started", "web_search_completed", "web_search_failed",
             "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed",
             "mcp_tool_call",
             "process_paused", "process_resumed",
             "plan_step", "plan_step_update", "planning_auto_reset",
             "debug_phase_update", "debug_user_request", "debug_resolved",
             "debug_native_session",
             "semantic_search", "read_lints",
             "file_change", "edit":
            return true
        default:
            return false
        }
    }

    func clearSwarmCards(for conversationId: UUID? = nil) {
        if let scope = normalizedConversationScope(conversationId) {
            let scopedIds = swarmCards.compactMap { key, card in
                cardBelongsToConversation(card, scope: scope) ? key : nil
            }
            guard !scopedIds.isEmpty else { return }
            for cardId in scopedIds {
                swarmCards.removeValue(forKey: cardId)
                swarmCardDedupKeys.removeValue(forKey: cardId)
            }
            markSortedSwarmCardsDirty()
            swarmEventsReceivedCount += 1
            return
        }

        if swarmEventsReceivedCount > 0 {
            swarmLogger.debug("Swarm stats: received=\(self.swarmEventsReceivedCount) assigned=\(self.swarmEventsAssignedCount) fallback=\(self.swarmEventsFallbackCount) cards=\(self.swarmCards.count)")
        }
        swarmCards.removeAll()
        swarmCardDedupKeys.removeAll()
        sortedSwarmCardsCache.removeAll()
        scopedSwarmCardsCache.removeAll()
        isSortedSwarmCardsCacheDirty = false
        swarmEventsReceivedCount = 0
        swarmEventsAssignedCount = 0
        swarmEventsFallbackCount = 0
        rebuildSwarmCards()
        swarmEventsReceivedCount += 1
    }

    /// Mark all cards still in `.running` status as `.completed`.
    /// Called when the parent task ends so the panel doesn't show
    /// stale running indicators after the stream finishes.
    func finalizeRunningSwarmCards(for conversationId: UUID? = nil) {
        let scope = normalizedConversationScope(conversationId)
        var didChange = false
        for (key, var card) in swarmCards where card.status == .running {
            if let scope, !cardBelongsToConversation(card, scope: scope) {
                continue
            }
            card.status = .completed
            card.completedAt = Date()
            card.activeOpsCount = 0
            card.isCollapsed = true
            card.hasUnreadSinceCollapse = false
            swarmCards[key] = card
            didChange = true
        }
        if didChange {
            markSortedSwarmCardsDirty()
            swarmEventsReceivedCount += 1
        }
    }

    func finalizeSwarmCards(
        withIDs swarmIds: Set<String>,
        for conversationId: UUID? = nil
    ) {
        guard !swarmIds.isEmpty else { return }
        let scope = normalizedConversationScope(conversationId)
        var didChange = false
        for swarmId in swarmIds {
            guard var card = swarmCards[swarmId], card.status == .running else {
                continue
            }
            if let scope, !cardBelongsToConversation(card, scope: scope) {
                continue
            }
            card.status = .completed
            card.completedAt = Date()
            card.activeOpsCount = 0
            card.isCollapsed = true
            card.hasUnreadSinceCollapse = false
            swarmCards[swarmId] = card
            didChange = true
        }
        if didChange {
            markSortedSwarmCardsDirty()
            swarmEventsReceivedCount += 1
        }
    }

    func setSwarmCardCollapsed(_ swarmId: String, collapsed: Bool) {
        guard var card = swarmCards[swarmId] else { return }
        card.isCollapsed = collapsed
        if !collapsed {
            card.hasUnreadSinceCollapse = false
        }
        swarmCards[swarmId] = card
        markSortedSwarmCardsDirty()
    }

    func swarmCardStates(
        for conversationId: UUID? = nil,
        limitEventsPerCard: Int = SwarmLiveReducer.defaultRecentEventsLimit
    )
        -> [SwarmLiveCardState]
    {
        if let conversationId {
            let scope = conversationId.uuidString.lowercased()
            if limitEventsPerCard == defaultSwarmEventsLimit {
                if let cached = scopedSwarmCardsCache[scope] {
                    return cached
                }
                let scoped = currentSortedSwarmCardsSnapshot().compactMap { card -> SwarmLiveCardState? in
                    let scopedEvents = card.recentEvents.filter {
                        activityBelongsToConversation($0, scope: scope)
                    }
                    guard !scopedEvents.isEmpty else { return nil }
                    return SwarmLiveReducer.reduce(
                        activities: scopedEvents,
                        limitRecentEvents: defaultSwarmEventsLimit
                    )[card.swarmId]
                }
                let sortedScoped = SwarmLiveReducer.sorted(states: scoped)
                scopedSwarmCardsCache[scope] = sortedScoped
                return sortedScoped
            }
            let reduced = SwarmLiveReducer.reduce(
                activities: scopedActivities(for: conversationId),
                limitRecentEvents: limitEventsPerCard
            )
            return SwarmLiveReducer.sorted(states: Array(reduced.values))
        }

        if limitEventsPerCard != defaultSwarmEventsLimit {
            let reduced = SwarmLiveReducer.reduce(
                activities: activities,
                limitRecentEvents: limitEventsPerCard
            )
            return SwarmLiveReducer.sorted(states: Array(reduced.values))
        }
        return currentSortedSwarmCardsSnapshot()
    }

    func swarmCardStatesIncludingPending(
        for conversationId: UUID? = nil,
        limitEventsPerCard: Int = SwarmLiveReducer.defaultRecentEventsLimit
    ) -> [SwarmLiveCardState] {
        let mergedActivities = activities + pendingActivities
        if let conversationId {
            let scoped = mergedActivities.filter { activity in
                canonicalConversationScope(from: activity.payload) == conversationId.uuidString.lowercased()
            }
            let reduced = SwarmLiveReducer.reduce(
                activities: scoped,
                limitRecentEvents: limitEventsPerCard
            )
            return SwarmLiveReducer.sorted(states: Array(reduced.values))
        }

        let reduced = SwarmLiveReducer.reduce(
            activities: mergedActivities,
            limitRecentEvents: limitEventsPerCard
        )
        return SwarmLiveReducer.sorted(states: Array(reduced.values))
    }

    func finalizedSwarmCardSnapshotForTaskCompletion(
        for conversationId: UUID? = nil,
        limitEventsPerCard: Int = SwarmLiveReducer.defaultRecentEventsLimit
    ) -> [SwarmLiveCardState] {
        let cards = swarmCardStatesIncludingPending(
            for: conversationId,
            limitEventsPerCard: limitEventsPerCard
        )
        let finalizedCards = cards.map(Self.finalizedSwarmCardSnapshot)
        scheduleDeferredMutation { store in
            store.flushPending()
            store.finalizeSwarmCards(
                matchingSnapshots: finalizedCards,
                for: conversationId
            )
        }
        return finalizedCards
    }

    func recentActivities(limit: Int) -> [TaskActivity] {
        guard limit > 0 else { return [] }
        return Array(activities.suffix(limit))
    }

    func planRelevantRecentActivities(limit: Int = 60) -> [TaskActivity] {
        recentActivities(limit: limit).filter(isPlanRelevantActivity(_:))
    }

    func swarmIds() -> [String] {
        let ids = activities.compactMap { SwarmMetadata.swarmId(from: $0.payload) }
            .filter { !$0.isEmpty }
        return Array(Set(ids)).sorted()
    }

    func activities(forSwarmId swarmId: String, limit: Int = 80) -> [TaskActivity] {
        recentActivities(limit: max(limit, 1)).filter { SwarmMetadata.swarmId(from: $0.payload) == swarmId }
    }

    func activitiesForSwarmLane(_ swarmId: String, limit: Int = 120) -> [TaskActivity] {
        let maxLimit = max(limit, 1)
        let sorted = activities.sorted { $0.timestamp < $1.timestamp }
        let direct = sorted.filter {
            SwarmMetadata.swarmId(from: $0.payload) == swarmId
        }
        let correlated = sorted.filter {
            let directSwarmId = $0.payload["swarm_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard directSwarmId.isEmpty,
                  let resolvedSwarmId = SwarmMetadata.swarmId(from: $0.payload),
                  resolvedSwarmId == swarmId else {
                return false
            }
            return true
        }
        var seen = Set<UUID>()
        let merged = (direct + correlated).filter { seen.insert($0.id).inserted }
        return Array(merged.suffix(maxLimit))
    }

    static func activitiesGroupedBySwarm(
        from activities: [TaskActivity],
        limitPerLane: Int = 120,
        includeCorrelatedGlobal: Bool = true
    ) -> [String: [TaskActivity]] {
        let effectiveLimit = max(1, limitPerLane)
        let sorted = activities.sorted { $0.timestamp < $1.timestamp }

        var grouped: [String: [TaskActivity]] = [:]
        for activity in sorted {
            guard let swarmId = SwarmMetadata.swarmId(from: activity.payload), !swarmId.isEmpty else { continue }
            grouped[swarmId, default: []].append(activity)
        }

        guard includeCorrelatedGlobal else {
            return grouped.mapValues { Array($0.suffix(effectiveLimit)) }
        }

        let correlated = correlatedGlobalActivities(from: sorted, swarmIds: Set(grouped.keys))
        for (swarmId, events) in correlated {
            var seen = Set(grouped[swarmId, default: []].map(\.id))
            for event in events where seen.insert(event.id).inserted {
                grouped[swarmId, default: []].append(event)
            }
        }

        return grouped.mapValues { events in
            Array(events.sorted { $0.timestamp < $1.timestamp }.suffix(effectiveLimit))
        }
    }

    static func correlatedGlobalActivities(
        from activities: [TaskActivity],
        swarmIds: Set<String>
    ) -> [String: [TaskActivity]] {
        guard !swarmIds.isEmpty else { return [:] }
        var out: [String: [TaskActivity]] = [:]
        for activity in activities {
            if let directSwarmId = activity.payload["swarm_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !directSwarmId.isEmpty {
                continue
            }
            guard let swarmId = SwarmMetadata.swarmId(from: activity.payload) else { continue }
            guard swarmIds.contains(swarmId) else { continue }
            out[swarmId, default: []].append(activity)
        }
        return out
    }

    static func laneStates(
        from activities: [TaskActivity],
        limitPerLane: Int = 120
    ) -> [SwarmLaneState] {
        let cards = SwarmLiveReducer.reduce(activities: activities, limitRecentEvents: limitPerLane)
        let states: [SwarmLaneState] = cards.values.map { card in
            let status: SwarmLaneStatus = {
                switch card.status {
                case .running: return .running
                case .failed: return .failed
                case .completed: return .completed
                case .idle: return .idle
                }
            }()
            return SwarmLaneState(
                id: card.swarmId,
                swarmId: card.swarmId,
                status: status,
                lastEventAt: card.lastEventAt,
                currentActivityTitle: card.currentStepTitle,
                events: card.recentEvents,
                activeOpsCount: card.activeOpsCount,
                errorsCount: card.errorCount,
                hasUnreadWhileCollapsed: card.hasUnreadSinceCollapse
            )
        }
        return states.sorted { lhs, rhs in
            let lw = laneSortWeight(lhs.status)
            let rw = laneSortWeight(rhs.status)
            if lw != rw { return lw < rw }
            return (lhs.lastEventAt ?? .distantPast) > (rhs.lastEventAt ?? .distantPast)
        }
    }

    static func laneSortWeight(_ status: SwarmLaneStatus) -> Int {
        switch status {
        case .running: return 0
        case .failed: return 1
        case .completed: return 2
        case .idle: return 3
        }
    }

    static func laneStatus(for events: [TaskActivity]) -> SwarmLaneStatus {
        guard !events.isEmpty else { return .idle }
        if events.contains(where: \.isRunning) { return .running }
        if let last = events.last {
            if isErrorEvent(last) { return .failed }
            if let detail = last.payload["detail"]?.lowercased(), detail == "completed" { return .completed }
            if last.type == "agent", last.detail?.lowercased() == "completed" { return .completed }
        }
        if events.contains(where: isErrorEvent) { return .failed }
        return .completed
    }

    static func isErrorEvent(_ activity: TaskActivity) -> Bool {
        let normalizedType = activity.type.lowercased()
        if ["web_search_failed", "web_fetch_failed", "tool_execution_error", "tool_validation_error", "tool_timeout", "permission_denied", "error"].contains(normalizedType) {
            return true
        }
        let status = (activity.payload["status"] ?? "").lowercased()
        if status == "error" || status == "fatal" {
            return true
        }
        let severity = (activity.payload["severity"] ?? "").lowercased()
        return severity == "error" || severity == "critical"
    }

    private func normalizedConversationScope(_ conversationId: UUID?) -> String? {
        guard let conversationId else { return nil }
        return conversationId.uuidString.lowercased()
    }

    private func scopedActivities(for conversationId: UUID) -> [TaskActivity] {
        let scope = conversationId.uuidString.lowercased()
        return activities.filter { activityBelongsToConversation($0, scope: scope) }
    }

    private func cardBelongsToConversation(_ card: SwarmLiveCardState, scope: String) -> Bool {
        card.recentEvents.contains(where: { activityBelongsToConversation($0, scope: scope) })
    }

    private func activityBelongsToConversation(_ activity: TaskActivity, scope: String) -> Bool {
        canonicalConversationScope(from: activity.payload) == scope
    }

    private static func finalizedSwarmCardSnapshot(_ card: SwarmLiveCardState) -> SwarmLiveCardState {
        guard card.status == .running else { return card }
        var finalized = card
        finalized.status = .completed
        finalized.completedAt = finalized.lastEventAt ?? Date()
        finalized.activeOpsCount = 0
        finalized.isCollapsed = true
        finalized.hasUnreadSinceCollapse = false
        return finalized
    }

    private func finalizeSwarmCards(
        matchingSnapshots snapshots: [SwarmLiveCardState],
        for conversationId: UUID? = nil
    ) {
        guard !snapshots.isEmpty else { return }
        let scope = normalizedConversationScope(conversationId)
        var didChange = false
        for snapshot in snapshots where snapshot.status == .completed {
            guard var liveCard = swarmCards[snapshot.swarmId], liveCard.status == .running else {
                continue
            }
            if let scope, !cardBelongsToConversation(liveCard, scope: scope) {
                continue
            }
            guard Self.isSameSwarmTurn(liveCard, snapshot: snapshot) else {
                continue
            }
            liveCard.status = .completed
            liveCard.completedAt = snapshot.completedAt ?? liveCard.lastEventAt ?? Date()
            liveCard.activeOpsCount = 0
            liveCard.isCollapsed = true
            liveCard.hasUnreadSinceCollapse = false
            swarmCards[snapshot.swarmId] = liveCard
            didChange = true
        }
        if didChange {
            markSortedSwarmCardsDirty()
            swarmEventsReceivedCount += 1
        }
    }

    private static func isSameSwarmTurn(
        _ liveCard: SwarmLiveCardState,
        snapshot: SwarmLiveCardState
    ) -> Bool {
        liveCard.startedAt == snapshot.startedAt
            && liveCard.lastEventAt == snapshot.lastEventAt
            && liveCard.recentEvents.last?.id == snapshot.recentEvents.last?.id
    }
}
