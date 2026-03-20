use super::common::{action, conversation_with_messages, message, unwrap_snapshot};
use crate::main_chat::store::handle_action;
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
