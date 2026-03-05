import Foundation

func resolveTaskStatusConversationId(
    activityPayload: [String: String],
    fallbackConversationId: UUID?
) -> UUID? {
    if let scope = canonicalConversationScope(from: activityPayload),
       let parsedConversationId = UUID(uuidString: scope) {
        return parsedConversationId
    }
    return fallbackConversationId
}

func payloadWithConversationScope(
    payload: [String: String],
    conversationId: UUID?
) -> [String: String] {
    var updated = payload
    if let scopedConversationId = canonicalConversationScope(from: updated) {
        updated["conversation_id"] = scopedConversationId
        return updated
    }
    guard let conversationId else { return updated }
    if canonicalConversationScopeValue(updated["conversation_id"]) == nil {
        updated["conversation_id"] = conversationId.uuidString.lowercased()
    }
    return updated
}
