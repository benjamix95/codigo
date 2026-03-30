import Foundation
import CoderEngine

func preferredConversationForTaskActivityDependentRefresh(
    selectedConversationId: UUID?,
    storeConversation: Conversation?,
    snapshotConversation: Conversation?
) -> Conversation? {
    guard let selectedConversationId else {
        return storeConversation ?? snapshotConversation
    }

    if let storeConversation, storeConversation.id == selectedConversationId {
        return storeConversation
    }
    if let snapshotConversation, snapshotConversation.id == selectedConversationId {
        return snapshotConversation
    }

    return nil
}
