import Foundation

func canonicalConversationScopeValue(_ rawConversationId: String?) -> String? {
    guard let rawConversationId = rawConversationId?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !rawConversationId.isEmpty,
        let parsedConversationId = UUID(uuidString: rawConversationId)
    else {
        return nil
    }
    return parsedConversationId.uuidString.lowercased()
}

func canonicalConversationScope(from payload: [String: String]) -> String? {
    if let snakeCase = canonicalConversationScopeValue(payload["conversation_id"]) {
        return snakeCase
    }
    if let camelCase = canonicalConversationScopeValue(payload["conversationId"]) {
        return camelCase
    }
    return nil
}
