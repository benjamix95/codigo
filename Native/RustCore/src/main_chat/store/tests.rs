use super::handle_action;
use app_core_protocol::main_chat_store::{
    MainChatStoreActionRequest, MainChatStoreCheckpointSnapshot, MainChatStoreConversationSnapshot,
    MainChatStoreMessageSnapshot, MainChatStoreResponse, MainChatStoreSnapshot,
};

fn empty_snapshot() -> MainChatStoreSnapshot {
    MainChatStoreSnapshot {
        conversations: Vec::new(),
        plan_boards: Default::default(),
    }
}

fn action(snapshot: MainChatStoreSnapshot, action: &str) -> MainChatStoreActionRequest {
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
    }
}

fn unwrap_snapshot(response: MainChatStoreResponse) -> MainChatStoreSnapshot {
    assert!(response.error.is_none());
    response.snapshot.unwrap()
}

#[test]
fn reducer_can_create_append_checkpoint_and_rewind() {
    let conversation = MainChatStoreConversationSnapshot {
        id: "conv-1".to_string(),
        thread_root_conversation_id: "conv-1".to_string(),
        title: "Test".to_string(),
        messages: Vec::new(),
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
    };
    let mut request = action(empty_snapshot(), "create_conversation");
    request.conversation = Some(conversation);
    let snapshot = unwrap_snapshot(handle_action(request));
    assert_eq!(snapshot.conversations.len(), 1);

    let message = MainChatStoreMessageSnapshot {
        id: "msg-1".to_string(),
        role: "user".to_string(),
        content: "hello".to_string(),
        primary_text_snapshot: Some("hello".to_string()),
        blocks: None,
        turn_metadata: None,
        is_streaming: false,
        image_paths: None,
        attachments: None,
        plan_attachment: None,
        reasoning_text: None,
        subagent_cards: None,
    };
    let mut append = action(snapshot, "append_message");
    append.conversation_id = Some("conv-1".to_string());
    append.message = Some(message);
    let snapshot = unwrap_snapshot(handle_action(append));
    assert_eq!(snapshot.conversations[0].messages.len(), 1);

    let checkpoint = MainChatStoreCheckpointSnapshot {
        id: "cp-1".to_string(),
        created_at: Some(2.0),
        message_count: 0,
        plan_board_snapshot: None,
        linked_plan_conversation_id: None,
        linked_plan_board_snapshot: None,
        git_states: Vec::new(),
    };
    let mut checkpoint_request = action(snapshot, "create_checkpoint");
    checkpoint_request.conversation_id = Some("conv-1".to_string());
    checkpoint_request.checkpoint = Some(checkpoint);
    let snapshot = unwrap_snapshot(handle_action(checkpoint_request));
    assert_eq!(snapshot.conversations[0].checkpoints.len(), 1);
    assert_eq!(snapshot.conversations[0].checkpoints[0].message_count, 1);

    let second_message = MainChatStoreMessageSnapshot {
        id: "msg-2".to_string(),
        role: "assistant".to_string(),
        content: "world".to_string(),
        primary_text_snapshot: Some("world".to_string()),
        blocks: None,
        turn_metadata: None,
        is_streaming: false,
        image_paths: None,
        attachments: None,
        plan_attachment: None,
        reasoning_text: None,
        subagent_cards: None,
    };
    let mut second_append = action(snapshot, "append_message");
    second_append.conversation_id = Some("conv-1".to_string());
    second_append.message = Some(second_message);
    let snapshot = unwrap_snapshot(handle_action(second_append));
    assert_eq!(snapshot.conversations[0].messages.len(), 2);

    let mut rewind = action(snapshot, "rewind_to_checkpoint");
    rewind.conversation_id = Some("conv-1".to_string());
    rewind.checkpoint_id = Some("cp-1".to_string());
    let snapshot = unwrap_snapshot(handle_action(rewind));
    assert_eq!(snapshot.conversations[0].messages.len(), 1);
    assert_eq!(snapshot.conversations[0].checkpoints.len(), 0);
}

#[test]
fn set_streaming_state_targets_active_streaming_assistant_before_reasoning_tail() {
    let conversation = MainChatStoreConversationSnapshot {
        id: "conv-stream".to_string(),
        thread_root_conversation_id: "conv-stream".to_string(),
        title: "Streaming".to_string(),
        messages: vec![
            message("user-1", "user", "hello", false),
            message("assistant-stream", "assistant", "", true),
            message("assistant-reasoning", "assistant", "thinking", false),
        ],
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
    };
    let mut request = action(
        MainChatStoreSnapshot {
            conversations: vec![conversation],
            plan_boards: Default::default(),
        },
        "set_streaming_state",
    );
    request.conversation_id = Some("conv-stream".to_string());
    request.bool_value = Some(false);
    let snapshot = unwrap_snapshot(handle_action(request));
    let messages = &snapshot.conversations[0].messages;
    assert_eq!(messages[1].is_streaming, false);
    assert_eq!(messages[2].is_streaming, false);
}

fn message(id: &str, role: &str, content: &str, is_streaming: bool) -> MainChatStoreMessageSnapshot {
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
