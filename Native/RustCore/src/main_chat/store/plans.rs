use super::models::{conversation_index, request_plan_board, upsert_plan_board};
use app_core_protocol::main_chat_store::{
    MainChatStoreActionRequest, MainChatStoreResponse, MainChatStoreSnapshot,
};

pub fn set_plan_board(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error(
            "missing_conversation_id",
            "conversationId is required",
        );
    };
    let plan_board = match request_plan_board(request) {
        Ok(plan_board) => plan_board.clone(),
        Err(error) => return error,
    };
    upsert_plan_board(&mut snapshot, conversation_id, plan_board);
    MainChatStoreResponse::success(snapshot)
}

pub fn remove_plan_board(
    mut snapshot: MainChatStoreSnapshot,
    conversation_id: &str,
) -> MainChatStoreResponse {
    snapshot.plan_boards.remove(conversation_id);
    MainChatStoreResponse::success(snapshot)
}

pub fn attach_plan_to_message(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error(
            "missing_conversation_id",
            "conversationId is required",
        );
    };
    let Some(message_id) = request.message_id.as_deref() else {
        return MainChatStoreResponse::error("missing_message_id", "messageId is required");
    };
    let Some(conversation_index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let Some(message_index) = snapshot.conversations[conversation_index]
        .messages
        .iter()
        .position(|item| item.id == message_id)
    else {
        return MainChatStoreResponse::error("missing_message", "message not found");
    };
    snapshot.conversations[conversation_index].messages[message_index].plan_attachment = request
        .message
        .as_ref()
        .and_then(|item| item.plan_attachment.clone());
    MainChatStoreResponse::success(snapshot)
}
