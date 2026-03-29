import Foundation

extension SwarmLiveReducer {
    static func canonicalize(
        _ activity: TaskActivity,
        existingCards: [String: SwarmLiveCardState]
    ) -> TaskActivity {
        guard let aliasSwarmId = aliasedSwarmId(
            for: activity,
            existingCards: existingCards
        ) else {
            return activity
        }

        var payload = activity.payload
        payload["swarm_id"] = aliasSwarmId
        payload["group_id"] = "swarm-\(aliasSwarmId)"
        return TaskActivity(
            id: activity.id,
            type: activity.type,
            title: activity.title,
            detail: activity.detail,
            payload: payload,
            timestamp: activity.timestamp,
            phase: activity.phase,
            isRunning: activity.isRunning,
            groupId: "swarm-\(aliasSwarmId)"
        )
    }

    private static func aliasedSwarmId(
        for activity: TaskActivity,
        existingCards: [String: SwarmLiveCardState]
    ) -> String? {
        guard let owner = ownerSwarmId(for: activity, includeOrchestratorFallback: false),
              existingCards[owner] == nil else {
            return nil
        }
        guard isLifecycleBoundaryEvent(activity) else { return nil }

        let conversationScope = canonicalConversationScope(from: activity.payload)
        let signature = identitySignature(for: activity)
        guard !signature.isEmpty else { return nil }

        let candidates = existingCards.values.filter { card in
            guard card.status == .running else { return false }
            if let conversationScope,
               !card.recentEvents.contains(where: {
                   canonicalConversationScope(from: $0.payload) == conversationScope
               }) {
                return false
            }
            return identitySignature(for: card) == signature
        }

        guard candidates.count == 1, let candidate = candidates.first else {
            return nil
        }
        return candidate.swarmId
    }

    private static func isLifecycleBoundaryEvent(_ activity: TaskActivity) -> Bool {
        let status = normalizedLifecycleStatus(activity)
        return status == .running || status == .completed || status == .failed
    }

    private static func identitySignature(for activity: TaskActivity) -> String {
        let name = normalizedIdentityName(
            activity.payload["readable_name"]
                ?? activity.payload["agent_name"]
                ?? activity.title
        )
        let role = normalizedIdentityToken(activity.payload["role"])
        let taskSummary = normalizedIdentityName(activity.payload["task_summary"])
        return [name, role, taskSummary]
            .filter { !$0.isEmpty }
            .joined(separator: "|")
    }

    private static func identitySignature(for card: SwarmLiveCardState) -> String {
        let name = normalizedIdentityName(card.displayName)
        let role = normalizedIdentityToken(card.roleType)
        let taskSummary = normalizedIdentityName(card.taskPrompt)
        return [name, role, taskSummary]
            .filter { !$0.isEmpty }
            .joined(separator: "|")
    }

    private static func normalizedIdentityName(_ raw: String?) -> String {
        let trimmed = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !trimmed.isEmpty else { return "" }

        let separators = [" — completed", " — failed", " - completed", " - failed"]
        for separator in separators where trimmed.hasSuffix(separator) {
            return String(trimmed.dropLast(separator.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private static func normalizedIdentityToken(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
    }
}
