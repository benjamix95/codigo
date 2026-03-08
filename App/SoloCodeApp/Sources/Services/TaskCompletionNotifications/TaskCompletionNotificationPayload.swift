import Foundation

struct TaskCompletionNotificationPayload: Equatable {
    let conversationId: UUID
    let assistantMessageId: UUID
    let title: String
    let body: String

    @MainActor
    static func build(
        from conversation: Conversation,
        formatter: TaskCompletionNotificationFormatter = .default
    ) -> TaskCompletionNotificationPayload? {
        guard let assistantIndex = lastFinalAssistantIndex(
            in: conversation.messages,
            formatter: formatter
        ) else {
            return nil
        }

        let assistantMessage = conversation.messages[assistantIndex]
        guard let finalAnswer = formatter.sanitizedNonEmptyText(assistantMessage.content) else {
            return nil
        }

        let lastUserQuestion = lastUserQuestion(
            before: assistantIndex,
            messages: conversation.messages,
            formatter: formatter
        )

        return TaskCompletionNotificationPayload(
            conversationId: conversation.id,
            assistantMessageId: assistantMessage.id,
            title: formatter.makeTitle(question: lastUserQuestion),
            body: formatter.makeBody(answer: finalAnswer)
        )
    }

    @MainActor
    private static func lastFinalAssistantIndex(
        in messages: [ChatMessage],
        formatter: TaskCompletionNotificationFormatter
    ) -> Int? {
        messages.indices.reversed().first { index in
            let message = messages[index]
            guard message.role == .assistant else { return false }
            guard !message.isStreaming else { return false }
            return formatter.sanitizedNonEmptyText(message.content) != nil
        }
    }

    @MainActor
    private static func lastUserQuestion(
        before assistantIndex: Int,
        messages: [ChatMessage],
        formatter: TaskCompletionNotificationFormatter
    ) -> String? {
        guard assistantIndex > 0 else { return nil }
        for index in stride(from: assistantIndex - 1, through: 0, by: -1) {
            let message = messages[index]
            guard message.role == .user else { continue }
            if let question = formatter.sanitizedNonEmptyText(message.content) {
                return question
            }
        }
        return nil
    }
}
