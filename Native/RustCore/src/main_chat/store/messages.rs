use super::models::{
    assistant_message_index, conversation_index, request_message, replace_message,
};
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
    if message.role == "assistant" && message.is_streaming {
        for existing in snapshot.conversations[index].messages.iter_mut() {
            if existing.role == "assistant" {
                existing.is_streaming = false;
            }
        }
    }
    snapshot.conversations[index].messages.push(message);
    MainChatStoreResponse::success(snapshot)
}

pub fn replace_or_update_message(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error("missing_conversation_id", "conversationId is required");
    };
    let Some(conversation_index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let conversation = &mut snapshot.conversations[conversation_index];
    let Some(message_index) = assistant_message_index(conversation, request.message_id.as_deref()) else {
        return MainChatStoreResponse::error("missing_message", "assistant message not found");
    };
    let mut message = conversation.messages[message_index].clone();
    if let Some(new_message) = request.message.clone() {
        message = new_message;
    } else {
        if let Some(text) = request.text.as_ref() {
            message.content = text.clone();
            message.primary_text_snapshot = Some(text.clone());
        }
        if let Some(flag) = request.bool_value {
            message.is_streaming = flag;
        }
    }
    replace_message(conversation, message_index, message);
    MainChatStoreResponse::success(snapshot)
}

pub fn save_reasoning(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error("missing_conversation_id", "conversationId is required");
    };
    let Some(conversation_index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let conversation = &mut snapshot.conversations[conversation_index];
    let Some(message_index) = assistant_message_index(conversation, request.message_id.as_deref()) else {
        return MainChatStoreResponse::error("missing_message", "assistant message not found");
    };
    if let Some(reasoning) = request.text.as_ref() {
        conversation.messages[message_index].reasoning_text = Some(reasoning.trim().to_string());
    }
    MainChatStoreResponse::success(snapshot)
}

pub fn set_streaming_state(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error("missing_conversation_id", "conversationId is required");
    };
    let Some(conversation_index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let conversation = &mut snapshot.conversations[conversation_index];
    let Some(message_index) = assistant_message_index(conversation, request.message_id.as_deref()) else {
        return MainChatStoreResponse::error("missing_message", "assistant message not found");
    };
    conversation.messages[message_index].is_streaming = request.bool_value.unwrap_or(false);
    MainChatStoreResponse::success(snapshot)
}

pub fn remove_message(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error("missing_conversation_id", "conversationId is required");
    };
    let Some(conversation_index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let conversation = &mut snapshot.conversations[conversation_index];
    let Some(message_id) = request.message_id.as_deref() else {
        return MainChatStoreResponse::error("missing_message_id", "messageId is required");
    };
    conversation.messages.retain(|item| item.id != message_id);
    conversation
        .checkpoints
        .retain(|item| item.message_count as usize <= conversation.messages.len());
    MainChatStoreResponse::success(snapshot)
}
