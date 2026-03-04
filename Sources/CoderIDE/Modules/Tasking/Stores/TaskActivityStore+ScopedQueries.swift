import Foundation

@MainActor
extension TaskActivityStore {
    func activities(for conversationId: UUID?) -> [TaskActivity] {
        guard let conversationId else { return activities }
        let scope = normalizedConversationScope(conversationId)
        return activities.filter { activity in
            normalizedConversationScope(activity.payload["conversation_id"]) == scope
        }
    }

    func nonSwarmActivities(for conversationId: UUID?) -> [TaskActivity] {
        activities(for: conversationId).filter { !SwarmMetadata.isSwarmEvent($0.payload) }
    }

    func concreteNonSwarmActivities(for conversationId: UUID?) -> [TaskActivity] {
        nonSwarmActivities(for: conversationId).filter { TaskActivityStore.isConcreteVisibleEvent($0) }
    }

    func planRelevantRecentActivities(limit: Int = 60, conversationId: UUID?) -> [TaskActivity] {
        let recent = planRelevantRecentActivities(limit: limit)
        guard let conversationId else { return recent }
        let scope = normalizedConversationScope(conversationId)
        return recent.filter { activity in
            normalizedConversationScope(activity.payload["conversation_id"]) == scope
        }
    }

    func instantGreps(for conversationId: UUID?) -> [InstantGrepResult] {
        guard let conversationId else { return instantGreps }
        return instantGreps.filter { $0.conversationId == conversationId }
    }

    private func normalizedConversationScope(_ conversationId: UUID) -> String {
        conversationId.uuidString.lowercased()
    }

    private func normalizedConversationScope(_ rawConversationId: String?) -> String {
        (rawConversationId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
