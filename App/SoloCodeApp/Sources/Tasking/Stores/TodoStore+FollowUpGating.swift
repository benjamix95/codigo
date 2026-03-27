import Foundation

extension TodoStore {
    func allowsPlanFollowUpMutation(
        title: String,
        conversationId: UUID?
    ) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if TodoExecutionFollowUpPolicy.isReviewTitle(trimmed) {
            return canonicalTodos(for: conversationId).contains {
                TodoExecutionFollowUpPolicy.isReviewTitle($0.title)
            }
        }

        if TodoExecutionFollowUpPolicy.isDocWriterTitle(trimmed) {
            return canonicalTodos(for: conversationId).contains {
                TodoExecutionFollowUpPolicy.isDocWriterTitle($0.title)
            }
        }

        return true
    }
}
