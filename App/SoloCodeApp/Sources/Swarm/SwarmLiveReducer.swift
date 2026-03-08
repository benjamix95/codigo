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
        // Skip transient "queued" placeholders — they use temporary IDs
        // that won't match the real subagent started/completed events.
        if owner.hasPrefix("queued-") { return }

        var card = cards[owner] ?? SwarmLiveCardState(swarmId: owner)
        if let agentName = activity.payload["agent_name"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !agentName.isEmpty {
            card.displayName = agentName
        } else if card.displayName.isEmpty,
                  let displayName = bestDisplayName(for: activity),
                  !displayName.isEmpty {
            card.displayName = displayName
        } else if card.displayName.isEmpty {
            card.displayName = owner
        }
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

        if activity.type == "subagent_text", let text = activity.payload["text"], !text.isEmpty {
            let remaining = SwarmLiveCardState.liveTextMaxLength - card.liveText.count
            if remaining > 0 {
                card.liveText += String(text.prefix(remaining))
            }
        }

        if let detail = bestDetail(for: activity, displayName: card.displayName) {
            card.currentDetail = detail
        }
        if !isDuplicate {
            if activity.isRunning {
                card.activeOpsCount += 1
            } else if card.activeOpsCount > 0 {
                card.activeOpsCount -= 1
            }
            if isErrorEvent(activity) {
                card.errorCount += 1
            } else if isWarningEvent(activity) {
                card.warningCount += 1
            }
        }

        let transition = statusTransition(for: activity)
        switch transition {
        case .running:
            card.status = .running
            card.completedAt = nil
            card.summary = nil
            // Preserve errorCount across running transitions — errors from
            // previous phases should not be silently discarded when a card
            // re-enters running state (e.g. retry after failure).
            if card.isCollapsed {
                card.hasUnreadSinceCollapse = true
            }
        case .completed:
            card.status = .completed
            card.completedAt = activity.timestamp
            card.summary = summary(for: card.recentEvents)
            card.activeOpsCount = 0
            card.isCollapsed = true
            card.hasUnreadSinceCollapse = false
        case .failed:
            card.status = .failed
            card.activeOpsCount = 0
            if card.isCollapsed {
                card.hasUnreadSinceCollapse = true
            }
        case .none:
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
        if let swarmId = SwarmMetadata.swarmId(from: activity.payload) {
            return swarmId
        }
        return includeOrchestratorFallback ? "orchestrator" : nil
    }

    static func isSwarmCriticalTransition(_ activity: TaskActivity) -> Bool {
        guard ownerSwarmId(for: activity, includeOrchestratorFallback: false) != nil else {
            return false
        }
        if activity.type == "agent" {
            let detail = (activity.detail ?? activity.payload["detail"] ?? "").lowercased()
            if detail == "started" || detail == "completed" || detail == "failed" {
                return true
            }
        }
        return isErrorEvent(activity)
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
        // Check completed/failed BEFORE isRunning — an explicit "completed" detail
        // must take priority over the isRunning flag to prevent cards from being
        // stuck in running state when the stream marks them completed.
        if detail == "completed" || status == "completed" {
            return .completed
        }
        if activity.type == "agent", detail == "failed" || status == "failed" {
            return .failed
        }
        if detail == "started" || status == "started" || activity.isRunning {
            return .running
        }
        return .none
    }

    private static func isErrorEvent(_ activity: TaskActivity) -> Bool {
        let normalizedType = activity.type.lowercased()
        if [
            "web_search_failed", "web_fetch_failed", "tool_execution_error", "tool_validation_error", "tool_timeout",
            "permission_denied", "error",
        ].contains(normalizedType) {
            return true
        }
        let status = (activity.payload["status"] ?? "").lowercased()
        if status == "error" || status == "fatal" {
            return true
        }
        let severity = (activity.payload["severity"] ?? "").lowercased()
        return severity == "error" || severity == "critical"
    }

    private static func isWarningEvent(_ activity: TaskActivity) -> Bool {
        guard !isErrorEvent(activity) else { return false }
        let status = (activity.payload["status"] ?? "").lowercased()
        if status == "failed" || status == "warning" {
            return true
        }
        let severity = (activity.payload["severity"] ?? "").lowercased()
        if severity == "warning" {
            return true
        }
        return false
    }

    private static func summary(for events: [TaskActivity]) -> String {
        let titles = events.suffix(6).map(\.title).filter { !$0.isEmpty }
        guard !titles.isEmpty else { return "Swarm completed." }
        var seen = Set<String>()
        var compact: [String] = []
        for title in titles where seen.insert(title).inserted {
            compact.append(title)
            if compact.count == 3 { break }
        }
        return "Completed • " + compact.joined(separator: " → ")
    }

    private static func bestDetail(
        for activity: TaskActivity,
        displayName: String
    ) -> String? {
        let candidates = [
            activity.detail,
            activity.payload["detail"],
            activity.payload["summary"],
            activity.payload["query"],
            activity.payload["path"],
            activity.payload["command"],
            activity.payload["tool"],
            activity.payload["mcp_tool"],
            activity.payload["name"],
            activity.payload["uri"],
        ]
        for candidate in candidates {
            if let text = SwarmLivePresentation.normalizedSubtitleText(
                candidate,
                excluding: displayName
            ) {
                return text
            }
        }
        return nil
    }

    private static func bestDisplayName(for activity: TaskActivity) -> String? {
        let text = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.lowercased() != activity.type.lowercased() else {
            return nil
        }
        return text
    }

    private static func dedupeKey(for activity: TaskActivity, owner: String) -> String {
        // Use 500ms buckets (divide by 2) instead of 10ms to reduce boundary effects.
        // Events within the same 500ms window with identical properties are deduped.
        let bucket = Int(activity.timestamp.timeIntervalSince1970 * 2)
        let status = (activity.payload["status"] ?? "").lowercased()
        let gid = activity.groupId ?? activity.payload["group_id"] ?? SwarmMetadata.canonicalGroupId(from: activity.payload) ?? "-"
        let conversationScope = canonicalConversationScope(from: activity.payload) ?? "-"
        return [
            owner, conversationScope, gid, activity.type, activity.title, status, "\(bucket)",
        ].joined(separator: "|")
    }
}
