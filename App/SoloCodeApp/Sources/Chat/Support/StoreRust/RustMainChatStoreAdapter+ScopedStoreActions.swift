import Foundation
import CoderEngine

extension RustMainChatStoreAdapter {
    @MainActor
    static func applyScopedStoreAction(
        snapshot: MainChatStoreSnapshotBridge,
        to store: ChatStore,
        scope: RustMainChatStoreActionScope
    ) {
        let updatedConversations = snapshot.conversations.compactMap(conversation)
        store.applyScopedRustBridgeConversations(
            updatedConversations,
            removingConversationIds: scope.removeScopedConversationsIfMissing
                ? scope.conversationIds.subtracting(Set(updatedConversations.map(\.id)))
                : []
        )

        for conversationId in scope.planBoardConversationIds {
            if let boardSnapshot = snapshot.planBoards[conversationId.lowercasedString] {
                store.planBoards[conversationId] = planBoard(boardSnapshot)
            } else if scope.removeScopedPlanBoardsIfMissing {
                store.planBoards.removeValue(forKey: conversationId)
            }
        }
    }
}
