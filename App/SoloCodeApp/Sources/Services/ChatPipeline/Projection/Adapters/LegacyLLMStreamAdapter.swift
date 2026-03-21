import Foundation

enum LegacyLLMStreamAdapter {
    static func textReplaceEvent(
        content: String,
        conversationId: UUID,
        assistantMessageId: UUID,
        turnId: String,
        sequence: Int,
        providerId: String
    ) -> ChatPipelineEvent {
        ChatPipelineEvent(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId,
            sequence: sequence,
            source: providerId,
            kind: .textReplace,
            payload: [
                "replacement": content,
                "stream_id": "main",
                "provider_id": providerId,
            ]
        )
    }

    static func lifecycleEvent(
        kind: ChatPipelineEventKind,
        conversationId: UUID,
        assistantMessageId: UUID,
        turnId: String,
        sequence: Int,
        providerId: String,
        status: String,
        detail: String? = nil
    ) -> ChatPipelineEvent {
        var payload = [
            "status": status,
            "provider_id": providerId,
        ]
        if let detail, !detail.isEmpty {
            payload["detail"] = detail
        }
        return ChatPipelineEvent(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId,
            sequence: sequence,
            source: providerId,
            kind: kind,
            payload: payload
        )
    }
}
