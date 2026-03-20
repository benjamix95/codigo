use super::models::conversation_index;
use app_core_protocol::main_chat_store::{
    MainChatStoreActionRequest, MainChatStoreResponse, MainChatStoreSnapshot,
};

pub fn create_checkpoint(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error("missing_conversation_id", "conversationId is required");
    };
    let Some(index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let Some(mut checkpoint) = request.checkpoint.clone() else {
        return MainChatStoreResponse::error("missing_checkpoint", "checkpoint payload is required");
    };
    checkpoint.message_count = snapshot.conversations[index].messages.len() as i32;
    if checkpoint.plan_board_snapshot.is_none() {
        checkpoint.plan_board_snapshot = snapshot.plan_boards.get(conversation_id).cloned();
    }
    if let Some(linked_id) = checkpoint.linked_plan_conversation_id.as_deref() {
        if checkpoint.linked_plan_board_snapshot.is_none() {
            checkpoint.linked_plan_board_snapshot = snapshot.plan_boards.get(linked_id).cloned();
        }
    }
    snapshot.conversations[index].checkpoints.push(checkpoint);
    MainChatStoreResponse::success(snapshot)
}

pub fn rewind_to_checkpoint(
    mut snapshot: MainChatStoreSnapshot,
    checkpoint_id: &str,
    conversation_id: &str,
) -> MainChatStoreResponse {
    let Some(index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let Some(checkpoint_index) = snapshot.conversations[index]
        .checkpoints
        .iter()
        .rposition(|item| item.id == checkpoint_id) else {
        return MainChatStoreResponse::error("missing_checkpoint", "checkpoint not found");
    };
    let checkpoint = snapshot.conversations[index].checkpoints[checkpoint_index].clone();
    if checkpoint.message_count as usize > snapshot.conversations[index].messages.len() {
        return MainChatStoreResponse::error("invalid_checkpoint", "checkpoint message count exceeds messages");
    }
    snapshot.conversations[index].messages.truncate(checkpoint.message_count as usize);
    match checkpoint.plan_board_snapshot {
        Some(plan_board) => {
            snapshot.plan_boards.insert(conversation_id.to_string(), plan_board);
        }
        None => {
            snapshot.plan_boards.remove(conversation_id);
        }
    }
    if let Some(linked_id) = checkpoint.linked_plan_conversation_id.as_deref() {
        match checkpoint.linked_plan_board_snapshot {
            Some(plan_board) => {
                snapshot.plan_boards.insert(linked_id.to_string(), plan_board);
            }
            None => {
                snapshot.plan_boards.remove(linked_id);
            }
        }
    }
    snapshot.conversations[index].checkpoints.truncate(checkpoint_index);
    MainChatStoreResponse::success(snapshot)
}

pub fn rewind_to_message_count(
    mut snapshot: MainChatStoreSnapshot,
    message_count: i32,
    conversation_id: &str,
) -> MainChatStoreResponse {
    let Some(index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    if message_count < 0 || message_count as usize > snapshot.conversations[index].messages.len() {
        return MainChatStoreResponse::error("invalid_message_count", "messageCount out of bounds");
    }
    snapshot.conversations[index].messages.truncate(message_count as usize);
    snapshot.conversations[index]
        .checkpoints
        .retain(|item| item.message_count <= message_count);
    if let Some(last_checkpoint) = snapshot.conversations[index].checkpoints.last().cloned() {
        match last_checkpoint.plan_board_snapshot {
            Some(plan_board) => { snapshot.plan_boards.insert(conversation_id.to_string(), plan_board); }
            None => { snapshot.plan_boards.remove(conversation_id); }
        }
        if let Some(linked_id) = last_checkpoint.linked_plan_conversation_id.as_deref() {
            match last_checkpoint.linked_plan_board_snapshot {
                Some(plan_board) => { snapshot.plan_boards.insert(linked_id.to_string(), plan_board); }
                None => { snapshot.plan_boards.remove(linked_id); }
            }
        }
    } else {
        snapshot.plan_boards.remove(conversation_id);
    }
    MainChatStoreResponse::success(snapshot)
}
