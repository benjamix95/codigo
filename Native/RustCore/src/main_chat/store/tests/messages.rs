use super::common::{action, conversation_with_messages, message, unwrap_snapshot};
use crate::main_chat::store::{handle_action, load_snapshot};
use app_core_protocol::main_chat_store::MainChatStoreSnapshot;

#[test]
fn set_streaming_state_targets_active_streaming_assistant_before_reasoning_tail() {
    let mut request = action(
        MainChatStoreSnapshot {
            conversations: vec![conversation_with_messages(
                "conv-stream",
                "Streaming",
                vec![
                    message("user-1", "user", "hello", false),
                    message("assistant-stream", "assistant", "", true),
                    message("assistant-reasoning", "assistant", "thinking", false),
                ],
            )],
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

#[test]
fn insert_message_before_places_message_at_anchor_and_clears_stale_streaming() {
    let mut request = action(
        MainChatStoreSnapshot {
            conversations: vec![conversation_with_messages(
                "conv-insert",
                "Streaming",
                vec![
                    message("user-1", "user", "hello", false),
                    message("assistant-old-stream", "assistant", "", true),
                    message("assistant-anchor", "assistant", "", true),
                ],
            )],
            plan_boards: Default::default(),
        },
        "insert_message_before",
    );
    request.conversation_id = Some("conv-insert".to_string());
    request.message_id = Some("assistant-anchor".to_string());
    request.message = Some(message("assistant-inserted", "assistant", "thinking", true));

    let snapshot = unwrap_snapshot(handle_action(request));
    let messages = &snapshot.conversations[0].messages;
    assert_eq!(messages[2].id, "assistant-inserted");
    assert_eq!(messages[3].id, "assistant-anchor");
    assert!(!messages[1].is_streaming);
    assert!(messages[2].is_streaming);
    assert!(!messages[3].is_streaming);
}

#[test]
fn remove_trailing_empty_assistant_messages_keeps_non_empty_history() {
    let mut request = action(
        MainChatStoreSnapshot {
            conversations: vec![conversation_with_messages(
                "conv-clean",
                "Clean",
                vec![
                    message("user-1", "user", "hello", false),
                    message("assistant-1", "assistant", "reply", false),
                    message("assistant-2", "assistant", "", false),
                    message("assistant-3", "assistant", " \n ", false),
                ],
            )],
            plan_boards: Default::default(),
        },
        "remove_trailing_empty_assistant_messages",
    );
    request.conversation_id = Some("conv-clean".to_string());

    let snapshot = unwrap_snapshot(handle_action(request));
    let messages = &snapshot.conversations[0].messages;
    assert_eq!(messages.len(), 2);
    assert_eq!(messages[1].content, "reply");
}

#[test]
fn sync_assistant_content_targets_active_streaming_assistant_before_reasoning_tail() {
    let mut request = action(
        MainChatStoreSnapshot {
            conversations: vec![conversation_with_messages(
                "conv-sync",
                "Streaming",
                vec![
                    message("user-1", "user", "hello", false),
                    message("assistant-stream", "assistant", "", true),
                    message("assistant-reasoning", "assistant", "thinking", false),
                ],
            )],
            plan_boards: Default::default(),
        },
        "sync_assistant_content",
    );
    request.conversation_id = Some("conv-sync".to_string());
    request.text = Some("Final response".to_string());

    let snapshot = unwrap_snapshot(handle_action(request));
    let messages = &snapshot.conversations[0].messages;
    assert_eq!(messages[1].content, "Final response");
    assert_eq!(messages[2].content, "thinking");
}

#[test]
fn sync_assistant_pipeline_state_preserves_existing_visible_text_when_incoming_is_empty() {
    let mut request = action(
        MainChatStoreSnapshot {
            conversations: vec![conversation_with_messages(
                "conv-pipeline",
                "Pipeline",
                vec![
                    message("user-1", "user", "hello", false),
                    message("assistant-1", "assistant", "Visible answer", true),
                ],
            )],
            plan_boards: Default::default(),
        },
        "sync_assistant_pipeline_state",
    );
    request.conversation_id = Some("conv-pipeline".to_string());
    request.message_id = Some("assistant-1".to_string());
    request.message = Some(
        app_core_protocol::main_chat_store::MainChatStoreMessageSnapshot {
            id: "assistant-1".to_string(),
            role: "assistant".to_string(),
            content: String::new(),
            primary_text_snapshot: Some(String::new()),
            blocks: Some(vec![
                app_core_protocol::main_chat_store::MainChatStoreTimelineBlockSnapshot {
                    id: "status-1".to_string(),
                    kind: "status".to_string(),
                    title: Some("Status".to_string()),
                    text: "Completed".to_string(),
                    items: Vec::new(),
                    metadata: Default::default(),
                    is_collapsible: true,
                    is_collapsed_by_default: false,
                },
            ]),
            turn_metadata: None,
            is_streaming: false,
            image_paths: None,
            attachments: None,
            plan_attachment: None,
            reasoning_text: None,
            subagent_cards: None,
        },
    );

    let snapshot = unwrap_snapshot(handle_action(request));
    let message = &snapshot.conversations[0].messages[1];
    assert_eq!(message.content, "Visible answer");
    assert_eq!(
        message.primary_text_snapshot.as_deref(),
        Some("Visible answer")
    );
    let blocks = message.blocks.as_ref().expect("blocks");
    assert_eq!(blocks[0].kind, "primaryText");
    assert_eq!(blocks[0].text, "Visible answer");
    assert!(blocks.iter().any(|block| block.kind == "status"));
}

#[test]
fn sync_assistant_pipeline_state_preserves_existing_timeline_context_when_incoming_snapshot_is_partial(
) {
    let mut request = action(
        MainChatStoreSnapshot {
            conversations: vec![
                app_core_protocol::main_chat_store::MainChatStoreConversationSnapshot {
                    id: "conv-pipeline".to_string(),
                    thread_root_conversation_id: "conv-pipeline".to_string(),
                    title: "Pipeline".to_string(),
                    messages: vec![
                        message("user-1", "user", "hello", false),
                        app_core_protocol::main_chat_store::MainChatStoreMessageSnapshot {
                            id: "assistant-1".to_string(),
                            role: "assistant".to_string(),
                            content: "Visible answer".to_string(),
                            primary_text_snapshot: Some("Visible answer".to_string()),
                            blocks: Some(vec![
                            app_core_protocol::main_chat_store::MainChatStoreTimelineBlockSnapshot {
                                id: "primary-text".to_string(),
                                kind: "primaryText".to_string(),
                                title: None,
                                text: "Visible answer".to_string(),
                                items: Vec::new(),
                                metadata: Default::default(),
                                is_collapsible: false,
                                is_collapsed_by_default: false,
                            },
                            app_core_protocol::main_chat_store::MainChatStoreTimelineBlockSnapshot {
                                id: "reasoning".to_string(),
                                kind: "reasoning".to_string(),
                                title: Some("Thinking".to_string()),
                                text: "Inspecting files".to_string(),
                                items: Vec::new(),
                                metadata: Default::default(),
                                is_collapsible: true,
                                is_collapsed_by_default: true,
                            },
                            app_core_protocol::main_chat_store::MainChatStoreTimelineBlockSnapshot {
                                id: "commands".to_string(),
                                kind: "commands".to_string(),
                                title: Some("Commands executed".to_string()),
                                text: String::new(),
                                items: vec!["rg timeline".to_string()],
                                metadata: Default::default(),
                                is_collapsible: true,
                                is_collapsed_by_default: true,
                            },
                        ]),
                            turn_metadata: None,
                            is_streaming: true,
                            image_paths: None,
                            attachments: None,
                            plan_attachment: None,
                            reasoning_text: Some("Inspecting files".to_string()),
                            subagent_cards: Some(vec![
                            app_core_protocol::main_chat_store::MainChatStoreSubagentCardSnapshot {
                                swarm_id: "swarm-1".to_string(),
                                status: "running".to_string(),
                                title: "Worker".to_string(),
                                detail: "Scanning timeline".to_string(),
                                summary: None,
                                error_count: 0,
                                warning_count: None,
                                result_preview: None,
                                transcript: None,
                            },
                        ]),
                        },
                    ],
                    created_at: None,
                    context_id: None,
                    context_folder_path: None,
                    mode: Some("agent".to_string()),
                    preferred_provider_id: Some("codex".to_string()),
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
                },
            ],
            plan_boards: Default::default(),
        },
        "sync_assistant_pipeline_state",
    );
    request.conversation_id = Some("conv-pipeline".to_string());
    request.message_id = Some("assistant-1".to_string());
    request.message = Some(
        app_core_protocol::main_chat_store::MainChatStoreMessageSnapshot {
            id: "assistant-1".to_string(),
            role: "assistant".to_string(),
            content: String::new(),
            primary_text_snapshot: Some(String::new()),
            blocks: Some(vec![
                app_core_protocol::main_chat_store::MainChatStoreTimelineBlockSnapshot {
                    id: "status-1".to_string(),
                    kind: "status".to_string(),
                    title: Some("Status".to_string()),
                    text: "Completed".to_string(),
                    items: Vec::new(),
                    metadata: Default::default(),
                    is_collapsible: true,
                    is_collapsed_by_default: false,
                },
            ]),
            turn_metadata: None,
            is_streaming: false,
            image_paths: None,
            attachments: None,
            plan_attachment: None,
            reasoning_text: None,
            subagent_cards: None,
        },
    );

    let snapshot = unwrap_snapshot(handle_action(request));
    let message = &snapshot.conversations[0].messages[1];
    assert_eq!(message.content, "Visible answer");
    assert_eq!(message.reasoning_text.as_deref(), Some("Inspecting files"));
    assert_eq!(message.subagent_cards.as_ref().map(Vec::len), Some(1));
    let blocks = message.blocks.as_ref().expect("blocks");
    assert!(blocks
        .iter()
        .any(|block| block.kind == "primaryText" && block.text == "Visible answer"));
    assert!(blocks
        .iter()
        .any(|block| block.kind == "reasoning" && block.text == "Inspecting files"));
    assert!(blocks
        .iter()
        .any(|block| block.kind == "commands" && block.items == vec!["rg timeline".to_string()]));
    assert!(blocks
        .iter()
        .any(|block| block.kind == "status" && block.text == "Completed"));
}

#[test]
fn load_snapshot_normalizes_primary_text_and_reasoning_blocks() {
    let response = load_snapshot(MainChatStoreSnapshot {
        conversations: vec![
            app_core_protocol::main_chat_store::MainChatStoreConversationSnapshot {
                id: "conv-load".to_string(),
                thread_root_conversation_id: "conv-load".to_string(),
                title: "Load".to_string(),
                messages: vec![
                    app_core_protocol::main_chat_store::MainChatStoreMessageSnapshot {
                        id: "assistant-load".to_string(),
                        role: "assistant".to_string(),
                        content: "Visible answer".to_string(),
                        primary_text_snapshot: None,
                        blocks: None,
                        turn_metadata: None,
                        is_streaming: false,
                        image_paths: None,
                        attachments: None,
                        plan_attachment: None,
                        reasoning_text: Some("Thinking".to_string()),
                        subagent_cards: None,
                    },
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
            },
        ],
        plan_boards: Default::default(),
    });
    let snapshot = unwrap_snapshot(response);
    let message = &snapshot.conversations[0].messages[0];
    assert_eq!(
        message.primary_text_snapshot.as_deref(),
        Some("Visible answer")
    );
    let blocks = message.blocks.as_ref().expect("blocks");
    assert_eq!(
        blocks.first().map(|block| block.kind.as_str()),
        Some("primaryText")
    );
    assert!(blocks
        .iter()
        .any(|block| block.kind == "reasoning" && block.text == "Thinking"));
}
