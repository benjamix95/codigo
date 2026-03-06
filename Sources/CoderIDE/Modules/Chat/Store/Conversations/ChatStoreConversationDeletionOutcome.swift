import Foundation

struct ChatStoreConversationDeletionOutcome: Equatable {
    let autoCreatedReplacementId: UUID?

    static let none = ChatStoreConversationDeletionOutcome(autoCreatedReplacementId: nil)
}
