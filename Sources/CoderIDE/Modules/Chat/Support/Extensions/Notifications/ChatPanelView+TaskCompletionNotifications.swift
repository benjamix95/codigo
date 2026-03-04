import Foundation

func shouldNotifyTaskCompletion(outcome: ToolTraceTurnOutcome?) -> Bool {
    outcome == .success
}

@MainActor
func buildTaskCompletionNotificationPayload(
    conversation: Conversation?,
    outcome: ToolTraceTurnOutcome?,
    formatter: TaskCompletionNotificationFormatter = .default
) -> TaskCompletionNotificationPayload? {
    guard shouldNotifyTaskCompletion(outcome: outcome) else { return nil }
    guard let conversation else { return nil }
    return TaskCompletionNotificationPayload.build(from: conversation, formatter: formatter)
}

extension ChatPanelView {
    @MainActor
    internal func notifyTaskCompletionIfNeeded(
        conversationId: UUID?,
        outcome: ToolTraceTurnOutcome?
    ) {
        guard let conversationId else { return }
        guard let payload = buildTaskCompletionNotificationPayload(
            conversation: chatStore.conversation(for: conversationId),
            outcome: outcome
        ) else {
            return
        }

        Task {
            await TaskCompletionNotificationService.shared.deliver(payload: payload)
        }
    }
}
