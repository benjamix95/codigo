use super::models::{conversation_index, normalized_provider_id};
use app_core_protocol::main_chat_store::{
    MainChatStoreActionRequest, MainChatStoreResponse, MainChatStoreSnapshot,
};

pub fn create_conversation(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation) = request.conversation.clone() else {
        return MainChatStoreResponse::error(
            "missing_conversation",
            "conversation payload is required",
        );
    };
    snapshot.conversations.push(conversation);
    MainChatStoreResponse::success(snapshot)
}

pub fn delete_conversation(
    mut snapshot: MainChatStoreSnapshot,
    conversation_id: &str,
) -> MainChatStoreResponse {
    snapshot
        .conversations
        .retain(|item| item.id != conversation_id);
    snapshot.plan_boards.remove(conversation_id);
    MainChatStoreResponse::success(snapshot)
}

pub fn update_conversation_preferences(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error(
            "missing_conversation_id",
            "conversationId is required",
        );
    };
    let Some(index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let conversation = &mut snapshot.conversations[index];
    if let Some(title) = request.title.as_ref() {
        let trimmed = title.trim();
        if !trimmed.is_empty() {
            conversation.title = trimmed.to_string();
        }
    }
    if request.mode.is_some() {
        conversation.mode = request.mode.clone();
    }
    if request.provider_id.is_some() {
        conversation.preferred_provider_id = normalized_provider_id(request.provider_id.clone());
    }
    if request.context_id.is_some() {
        conversation.context_id = normalized_provider_id(request.context_id.clone());
    }
    if request.context_folder_path.is_some() {
        conversation.context_folder_path = request.context_folder_path.clone();
    }
    if request.workspace_id.is_some() {
        conversation.workspace_id = normalized_provider_id(request.workspace_id.clone());
    }
    if !request.string_list.is_empty() {
        conversation.ad_hoc_folder_paths = request.string_list.clone();
    }
    if let Some(flag) = request.bool_value {
        match request.action.as_str() {
            "set_archived" => conversation.is_archived = flag,
            "set_pinned" => conversation.is_pinned = flag,
            "set_favorite" => conversation.is_favorite = flag,
            _ => {}
        }
    }
    if let Some(last_input_tokens) = request.int_value {
        if request.action == "set_last_input_tokens" {
            conversation.last_input_tokens = Some(last_input_tokens);
        }
    }
    if request.action == "set_context_memory_summary" {
        conversation.context_memory_summary_markdown = request.text.clone();
        conversation.context_memory_generated_at = request.checkpoint.as_ref().and_then(|_| None);
        conversation.context_memory_source_message_count = request.int_value;
    }
    MainChatStoreResponse::success(snapshot)
}
