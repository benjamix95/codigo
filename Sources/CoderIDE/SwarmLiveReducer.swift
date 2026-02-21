import Foundation

enum SwarmLiveReducer {
    static let defaultRecentEventsLimit = 80

    static func reduce(
        activities: [TaskActivity],
        limitRecentEvents: Int = defaultRecentEventsLimit
    ) -> [String: SwarmLiveCardState] {
        var cards: [String: SwarmLiveCardState] = [:]
        var dedupeKeys: [String: Set<String>] = [:]
        for activity in activities.sorted(by: { $0.timestamp < $1.timestamp }) {
            apply(
                activity: activity,
                to: &cards,
                dedupeKeys: &dedupeKeys,
                limitRecentEvents: max(1, limitRecentEvents)
            )
        }
        return cards
    }

    static func apply(
        activity: TaskActivity,
        to cards: inout [String: SwarmLiveCardState],
        dedupeKeys: inout [String: Set<String>],
        limitRecentEvents: Int = defaultRecentEventsLimit
    ) {
        guard let owner = ownerSwarmId(for: activity, includeOrchestratorFallback: true) else {
            return
        }

        var card = cards[owner] ?? SwarmLiveCardState(swarmId: owner)
        let dedupeKey = dedupeKey(for: activity, owner: owner)
        var ownerKeys = dedupeKeys[owner] ?? Set<String>()
        let isDuplicate = ownerKeys.contains(dedupeKey)
        if !isDuplicate {
            ownerKeys.insert(dedupeKey)
            dedupeKeys[owner] = ownerKeys
            card.recentEvents.append(activity)
            if card.recentEvents.count > limitRecentEvents {
                card.recentEvents = Array(card.recentEvents.suffix(limitRecentEvents))
            }
        }

        card.startedAt = card.startedAt ?? activity.timestamp
        card.lastEventAt = max(card.lastEventAt ?? .distantPast, activity.timestamp)
        if !activity.title.isEmpty {
            card.currentStepTitle = activity.title
        }

        card.currentDetail = bestDetail(for: activity) ?? card.currentDetail
        card.activeOpsCount = card.recentEvents.suffix(limitRecentEvents).filter(\.isRunning).count
        card.errorCount = card.recentEvents.suffix(limitRecentEvents).filter(isErrorEvent).count

        let transition = statusTransition(for: activity)
        switch transition {
        case .running:
            card.status = .running
            card.completedAt = nil
            card.summary = nil
            if card.isCollapsed {
                card.hasUnreadSinceCollapse = true
            }
        case .completed:
            card.status = .completed
            card.completedAt = activity.timestamp
            card.summary = summary(for: card.recentEvents)
            card.isCollapsed = true
            card.hasUnreadSinceCollapse = false
        case .failed:
            card.status = .failed
            card.isCollapsed = false
            card.hasUnreadSinceCollapse = false
        case .none:
            if card.status == .idle {
                card.status = activity.isRunning ? .running : .completed
            }
            if card.isCollapsed && !isDuplicate {
                card.hasUnreadSinceCollapse = true
            }
        }

        cards[owner] = card
    }

    static func sorted(states: [SwarmLiveCardState]) -> [SwarmLiveCardState] {
        states.sorted { lhs, rhs in
            let lw = sortWeight(lhs.status)
            let rw = sortWeight(rhs.status)
            if lw != rw { return lw < rw }
            return (lhs.lastEventAt ?? .distantPast) > (rhs.lastEventAt ?? .distantPast)
        }
    }

    private static func sortWeight(_ status: SwarmCardStatus) -> Int {
        switch status {
        case .running: return 0
        case .failed: return 1
        case .completed: return 2
        case .idle: return 3
        }
    }

    static func ownerSwarmId(
        for activity: TaskActivity,
        includeOrchestratorFallback: Bool
    ) -> String? {
        if let swarmId = activity.payload["swarm_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !swarmId.isEmpty
        {
            return swarmId
        }
        if let groupId = activity.payload["group_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            groupId.hasPrefix("swarm-")
        {
            return String(groupId.dropFirst("swarm-".count))
        }
        return includeOrchestratorFallback ? "orchestrator" : nil
    }

    static func isSwarmCriticalTransition(_ activity: TaskActivity) -> Bool {
        if activity.type == "agent" {
            let detail = (activity.detail ?? activity.payload["detail"] ?? "").lowercased()
            if detail == "started" || detail == "completed" || detail == "failed" {
                return true
            }
        }
        if isErrorEvent(activity) { return true }
        let status = (activity.payload["status"] ?? "").lowercased()
        return status == "started" || status == "completed" || status == "failed"
    }

    private enum Transition {
        case running
        case completed
        case failed
        case none
    }

    private static func statusTransition(for activity: TaskActivity) -> Transition {
        if isErrorEvent(activity) { return .failed }
        let detail = (activity.detail ?? activity.payload["detail"] ?? "").lowercased()
        let status = (activity.payload["status"] ?? "").lowercased()
        if detail == "started" || status == "started" || activity.isRunning {
            return .running
        }
        if detail == "completed" || status == "completed" {
            return .completed
        }
        return .none
    }

    private static func isErrorEvent(_ activity: TaskActivity) -> Bool {
        if [
            "web_search_failed", "tool_execution_error", "tool_validation_error", "tool_timeout",
            "permission_denied", "error",
        ].contains(activity.type) {
            return true
        }
        let t = activity.title.lowercased()
        let d = (activity.detail ?? "").lowercased()
        let status = (activity.payload["status"] ?? "").lowercased()
        return t.contains("errore") || t.contains("failed") || d.contains("errore")
            || d.contains("failed") || status == "failed"
    }

    private static func summary(for events: [TaskActivity]) -> String {
        let titles = events.suffix(6).map(\.title).filter { !$0.isEmpty }
        guard !titles.isEmpty else { return "Swarm completato." }
        var seen = Set<String>()
        var compact: [String] = []
        for title in titles where seen.insert(title).inserted {
            compact.append(title)
            if compact.count == 3 { break }
        }
        return "Completato • " + compact.joined(separator: " → ")
    }

    private static func bestDetail(for activity: TaskActivity) -> String? {
        let candidates = [
            activity.detail,
            activity.payload["detail"],
            activity.payload["summary"],
            activity.payload["query"],
            activity.payload["path"],
            activity.payload["command"],
        ]
        for candidate in candidates {
            let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty { return text }
        }
        return nil
    }

    private static func dedupeKey(for activity: TaskActivity, owner: String) -> String {
        let bucket = Int(activity.timestamp.timeIntervalSince1970)
        let status = (activity.payload["status"] ?? "").lowercased()
        let gid = activity.groupId ?? activity.payload["group_id"] ?? "-"
        return [
            owner, gid, activity.type, activity.title, status, "\(bucket)",
        ].joined(separator: "|")
    }
}
