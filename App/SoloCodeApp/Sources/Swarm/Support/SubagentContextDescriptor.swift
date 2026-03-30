import Foundation

struct SubagentContextDescriptor: Equatable, Sendable {
    let primaryLabel: String
    let secondaryLabel: String?

    static func from(card: SwarmLiveCardState) -> SubagentContextDescriptor? {
        let payload = latestContextPayload(in: card)
        let childThreadID = normalized(payload["thread_id"])
        let parentThreadID = normalized(payload["sender_thread_id"])
        let taskID = normalized(payload["task_id"])

        if let childThreadID {
            let secondaryLabel = parentThreadID.map { "Parent \($0)" }
            return SubagentContextDescriptor(
                primaryLabel: "Contexto dedicato • sola lettura • Thread \(childThreadID)",
                secondaryLabel: secondaryLabel
            )
        }

        if let taskID {
            return SubagentContextDescriptor(
                primaryLabel: "Contexto dedicato • sola lettura • Task \(taskID)",
                secondaryLabel: nil
            )
        }

        if !card.taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !card.recentEvents.isEmpty
        {
            return SubagentContextDescriptor(
                primaryLabel: "Contexto dedicato • sola lettura",
                secondaryLabel: nil
            )
        }

        return nil
    }

    private static func latestContextPayload(in card: SwarmLiveCardState) -> [String: String] {
        for activity in card.recentEvents.reversed() {
            let payload = activity.payload
            if normalized(payload["thread_id"]) != nil
                || normalized(payload["sender_thread_id"]) != nil
                || normalized(payload["task_id"]) != nil
            {
                return payload
            }
        }
        return [:]
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
