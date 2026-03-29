import Foundation
import CoderEngine

struct RustMainChatStoreActionScope {
    let conversationIds: Set<UUID>
    let planBoardConversationIds: Set<UUID>
    let removeScopedConversationsIfMissing: Bool
    let removeScopedPlanBoardsIfMissing: Bool
}

extension ChatStore {
    @MainActor
    func rustStoreActionScope(
        for request: MainChatStoreActionRequestBridge
    ) -> RustMainChatStoreActionScope? {
        guard let conversationId = request.conversationId.flatMap(UUID.init(uuidString:)) else {
            return nil
        }

        switch request.action {
        case "create_conversation":
            return RustMainChatStoreActionScope(
                conversationIds: [conversationId],
                planBoardConversationIds: [],
                removeScopedConversationsIfMissing: false,
                removeScopedPlanBoardsIfMissing: false
            )
        case "append_message",
             "insert_message_before",
             "sync_assistant_content",
             "sync_assistant_pipeline_state",
             "save_reasoning",
             "save_subagent_cards_to_last_assistant",
             "set_streaming_state",
             "remove_trailing_empty_assistant_messages",
             "remove_assistant_message_if_empty",
             "remove_message",
             "set_archived",
             "set_pinned",
             "set_favorite",
             "set_title",
             "set_mode",
             "set_preferred_provider",
             "set_context",
             "set_context_folder",
             "set_workspace",
             "set_ad_hoc_paths",
             "set_last_input_tokens",
             "set_context_memory_summary",
             "create_checkpoint",
             "rewind_to_checkpoint",
             "rewind_to_message_count":
            return RustMainChatStoreActionScope(
                conversationIds: [conversationId],
                planBoardConversationIds: [],
                removeScopedConversationsIfMissing: request.action.hasPrefix("remove_"),
                removeScopedPlanBoardsIfMissing: false
            )
        case "delete_conversation":
            return RustMainChatStoreActionScope(
                conversationIds: [conversationId],
                planBoardConversationIds: [conversationId],
                removeScopedConversationsIfMissing: true,
                removeScopedPlanBoardsIfMissing: true
            )
        case "set_plan_board", "remove_plan_board":
            return RustMainChatStoreActionScope(
                conversationIds: [],
                planBoardConversationIds: [conversationId],
                removeScopedConversationsIfMissing: false,
                removeScopedPlanBoardsIfMissing: true
            )
        case "attach_plan_to_message":
            return RustMainChatStoreActionScope(
                conversationIds: [conversationId],
                planBoardConversationIds: [conversationId],
                removeScopedConversationsIfMissing: false,
                removeScopedPlanBoardsIfMissing: false
            )
        default:
            return nil
        }
    }

    @MainActor
    func scopedRustStoreSnapshot(
        for request: MainChatStoreActionRequestBridge,
        scope: RustMainChatStoreActionScope
    ) -> MainChatStoreSnapshotBridge {
        RustMainChatStoreAdapter.scopedSnapshot(
            from: self,
            conversationIds: scope.conversationIds,
            planBoardConversationIds: scope.planBoardConversationIds
        )
    }
}
