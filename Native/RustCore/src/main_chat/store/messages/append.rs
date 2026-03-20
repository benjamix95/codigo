use super::helpers::{clear_stale_assistant_streaming, update_new_conversation_title};
use crate::main_chat::store::models::{conversation_index, request_message};
use app_core_protocol::main_chat_store::{
    MainChatStoreActionRequest, MainChatStoreResponse, MainChatStoreSnapshot,
};

pub fn append_message(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error("missing_conversation_id", "conversationId is required");
    };
    let Some(index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let message = match request_message(request) {
        Ok(message) => message.clone(),
        Err(error) => return error,
    };

    let conversation = &mut snapshot.conversations[index];
    if message.role == "assistant" && message.is_streaming {
        clear_stale_assistant_streaming(conversation);
    }
    update_new_conversation_title(conversation, &message);
    conversation.messages.push(message);
    MainChatStoreResponse::success(snapshot)
}

pub fn insert_message_before(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error("missing_conversation_id", "conversationId is required");
    };
    let Some(index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let message = match request_message(request) {
        Ok(message) => message.clone(),
        Err(error) => return error,
    };

    let conversation = &mut snapshot.conversations[index];
    if message.role == "assistant" && message.is_streaming {
        clear_stale_assistant_streaming(conversation);
    }
    update_new_conversation_title(conversation, &message);

    if let Some(anchor_id) = request.message_id.as_deref() {
        if let Some(anchor_index) = conversation.messages.iter().position(|item| item.id == anchor_id) {
            conversation.messages.insert(anchor_index, message);
            return MainChatStoreResponse::success(snapshot);
        }
    }

    conversation.messages.push(message);
    MainChatStoreResponse::success(snapshot)
}
