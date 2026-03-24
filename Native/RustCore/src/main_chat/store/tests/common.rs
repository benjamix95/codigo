use app_core_protocol::main_chat_store::{
    MainChatStoreActionRequest, MainChatStoreCheckpointSnapshot, MainChatStoreConversationSnapshot,
    MainChatStoreMessageSnapshot, MainChatStoreResponse, MainChatStoreSnapshot,
};

pub fn empty_snapshot() -> MainChatStoreSnapshot {
    MainChatStoreSnapshot {
        conversations: Vec::new(),
        plan_boards: Default::default(),
    }
}

pub fn action(snapshot: MainChatStoreSnapshot, action: &str) -> MainChatStoreActionRequest {
    MainChatStoreActionRequest {
        schema_version: 1,
        action: action.to_string(),
        snapshot,
        conversation_id: None,
        message_id: None,
        checkpoint_id: None,
        message_count: None,
        conversation: None,
        message: None,
        plan_board: None,
        checkpoint: None,
        title: None,
        mode: None,
        provider_id: None,
        context_id: None,
        context_folder_path: None,
        workspace_id: None,
        bool_value: None,
        int_value: None,
        text: None,
        string_list: Vec::new(),
        subagent_cards: None,
    }
}

pub fn unwrap_snapshot(response: MainChatStoreResponse) -> MainChatStoreSnapshot {
    assert!(response.error.is_none());
    response.snapshot.unwrap()
}

pub fn conversation_with_messages(
    id: &str,
    title: &str,
    messages: Vec<MainChatStoreMessageSnapshot>,
) -> MainChatStoreConversationSnapshot {
    MainChatStoreConversationSnapshot {
        id: id.to_string(),
        thread_root_conversation_id: id.to_string(),
        title: title.to_string(),
        messages,
        created_at: Some(1.0),
        context_id: None,
        context_folder_path: None,
        mode: Some("agent".to_string()),
        preferred_provider_id: None,
        context_memory_summary_markdown: None,
        context_memory_generated_at: None,
        context_memory_source_message_count: None,
        is_archived: false,
        is_pinned: false,
        is_favorite: false,
        last_input_tokens: None,
        workspace_id: None,
        ad_hoc_folder_paths: Vec::new(),
        checkpoints: Vec::new(),
    }
}

pub fn checkpoint(id: &str) -> MainChatStoreCheckpointSnapshot {
    MainChatStoreCheckpointSnapshot {
        id: id.to_string(),
        created_at: Some(2.0),
        message_count: 0,
        plan_board_snapshot: None,
        linked_plan_conversation_id: None,
        linked_plan_board_snapshot: None,
        git_states: Vec::new(),
    }
}

pub fn message(
    id: &str,
    role: &str,
    content: &str,
    is_streaming: bool,
) -> MainChatStoreMessageSnapshot {
    MainChatStoreMessageSnapshot {
        id: id.to_string(),
        role: role.to_string(),
        content: content.to_string(),
        primary_text_snapshot: Some(content.to_string()),
        blocks: None,
        turn_metadata: None,
        is_streaming,
        image_paths: None,
        attachments: None,
        plan_attachment: None,
        reasoning_text: None,
        subagent_cards: None,
    }
}
