use app_core_protocol::main_chat_store::{
    MainChatStoreActionRequest, MainChatStoreConversationSnapshot, MainChatStoreMessageSnapshot,
    MainChatStorePlanBoardSnapshot, MainChatStoreResponse, MainChatStoreSnapshot,
};

pub fn validate_schema(version: i32) -> Result<(), MainChatStoreResponse> {
    if version != 1 {
        return Err(MainChatStoreResponse::error(
            "unsupported_schema",
            "schemaVersion must be 1",
        ));
    }
    Ok(())
}

pub fn conversation_index(snapshot: &MainChatStoreSnapshot, conversation_id: &str) -> Option<usize> {
    snapshot
        .conversations
        .iter()
        .position(|item| item.id == conversation_id)
}

pub fn assistant_message_index(conversation: &MainChatStoreConversationSnapshot, message_id: Option<&str>) -> Option<usize> {
    if let Some(message_id) = message_id {
        return conversation
            .messages
            .iter()
            .position(|item| item.id == message_id && item.role == "assistant");
    }
    conversation
        .messages
        .iter()
        .rposition(|item| item.role == "assistant")
}

pub fn normalized_provider_id(provider_id: Option<String>) -> Option<String> {
    provider_id.and_then(|value| {
        let trimmed = value.trim().to_string();
        if trimmed.is_empty() { None } else { Some(trimmed) }
    })
}

pub fn upsert_plan_board(
    snapshot: &mut MainChatStoreSnapshot,
    conversation_id: &str,
    plan_board: MainChatStorePlanBoardSnapshot,
) {
    snapshot
        .plan_boards
        .insert(conversation_id.to_string(), plan_board);
}

pub fn replace_message(
    conversation: &mut MainChatStoreConversationSnapshot,
    message_index: usize,
    message: MainChatStoreMessageSnapshot,
) {
    conversation.messages[message_index] = message;
}

pub fn request_conversation<'a>(
    request: &'a MainChatStoreActionRequest,
) -> Result<&'a MainChatStoreConversationSnapshot, MainChatStoreResponse> {
    request.conversation.as_ref().ok_or_else(|| {
        MainChatStoreResponse::error("missing_conversation", "conversation payload is required")
    })
}

pub fn request_message<'a>(
    request: &'a MainChatStoreActionRequest,
) -> Result<&'a MainChatStoreMessageSnapshot, MainChatStoreResponse> {
    request.message.as_ref().ok_or_else(|| {
        MainChatStoreResponse::error("missing_message", "message payload is required")
    })
}

pub fn request_plan_board<'a>(
    request: &'a MainChatStoreActionRequest,
) -> Result<&'a MainChatStorePlanBoardSnapshot, MainChatStoreResponse> {
    request.plan_board.as_ref().ok_or_else(|| {
        MainChatStoreResponse::error("missing_plan_board", "planBoard payload is required")
    })
}
