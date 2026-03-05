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

func payloadWithConversationScope(
    payload: [String: String],
    conversationId: UUID?
) -> [String: String] {
    guard let conversationId else { return payload }
    var updated = payload
    let taggedConversationId = (updated["conversation_id"] ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if taggedConversationId.isEmpty {
        updated["conversation_id"] = conversationId.uuidString.lowercased()
    }
    return updated
}
