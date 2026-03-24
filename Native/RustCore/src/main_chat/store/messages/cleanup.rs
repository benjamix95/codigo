use crate::main_chat::store::models::conversation_index;
use app_core_protocol::main_chat_store::{
    MainChatStoreActionRequest, MainChatStoreResponse, MainChatStoreSnapshot,
};

pub fn remove_trailing_empty_assistant_messages(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error(
            "missing_conversation_id",
            "conversationId is required",
        );
    };
    let Some(conversation_index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let conversation = &mut snapshot.conversations[conversation_index];
    while let Some(last) = conversation.messages.last() {
        let is_empty = last.content.trim().is_empty();
        if last.role != "assistant" || !is_empty || last.is_streaming {
            break;
        }
        conversation.messages.pop();
    }
    MainChatStoreResponse::success(snapshot)
}

pub fn remove_message(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error(
            "missing_conversation_id",
            "conversationId is required",
        );
    };
    let Some(conversation_index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let Some(message_id) = request.message_id.as_deref() else {
        return MainChatStoreResponse::error("missing_message_id", "messageId is required");
    };
    let conversation = &mut snapshot.conversations[conversation_index];
    conversation.messages.retain(|item| item.id != message_id);
    conversation
        .checkpoints
        .retain(|item| item.message_count as usize <= conversation.messages.len());
    MainChatStoreResponse::success(snapshot)
}
