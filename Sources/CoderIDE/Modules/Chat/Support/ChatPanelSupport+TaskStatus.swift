import Foundation

func resolveTaskStatusConversationId(
    activityPayload: [String: String],
    fallbackConversationId: UUID?
) -> UUID? {
    if let rawConversationId = activityPayload["conversation_id"]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !rawConversationId.isEmpty,
       let parsedConversationId = UUID(uuidString: rawConversationId)
    {
        return parsedConversationId
    }
    return fallbackConversationId
}
