import Foundation

extension ChatStore {
    func normalizeLoadedConversationsForColdStart(_ conversations: [Conversation]) -> [Conversation] {
        conversations.map { conversation in
            var normalized = conversation
            normalized.messages = conversation.messages.map { message in
                message.settledForColdStart()
            }
            return normalized
        }
    }
}

private extension ChatMessage {
    func settledForColdStart() -> ChatMessage {
        guard role == .assistant else { return self }

        var settled = self
        settled.isStreaming = false

        if var metadata = settled.turnMetadata {
            metadata.isStreaming = false
            let runningStatuses = ["streaming", "running", "started", "in_progress", "executing"]
            if runningStatuses.contains(metadata.status.lowercased()) {
                metadata.status = "completed"
                metadata.completedAt = metadata.completedAt ?? metadata.updatedAt ?? metadata.startedAt
            }
            settled.turnMetadata = metadata
        }

        return settled
    }
}
