use super::helpers::{
    assistant_target_index, last_assistant_index, normalize_message, resolved_primary_text,
    sync_primary_text_block,
};
use crate::main_chat::store::models::{conversation_index, replace_message};
use app_core_protocol::main_chat_store::{
    MainChatStoreActionRequest, MainChatStoreMessageSnapshot, MainChatStoreResponse,
    MainChatStoreSnapshot,
};

pub fn replace_or_update_message(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error(
            "missing_conversation_id",
            "conversationId is required",
        );
    };
    let Some(conversation_index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let conversation = &mut snapshot.conversations[conversation_index];
    let message_index = if let Some(message_id) = request.message_id.as_deref() {
        assistant_target_index(conversation, Some(message_id))
    } else {
        last_assistant_index(conversation)
    };
    let Some(message_index) = message_index else {
        return MainChatStoreResponse::error("missing_message", "assistant message not found");
    };

    let mut message = conversation.messages[message_index].clone();
    if let Some(new_message) = request.message.clone() {
        message = new_message;
    } else {
        if let Some(text) = request.text.as_ref() {
            sync_primary_text_block(&mut message, text);
        }
        if let Some(flag) = request.bool_value {
            message.is_streaming = flag;
        }
    }
    replace_message(conversation, message_index, message);
    MainChatStoreResponse::success(snapshot)
}

pub fn sync_assistant_content(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error(
            "missing_conversation_id",
            "conversationId is required",
        );
    };
    let Some(conversation_index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let Some(content) = request.text.as_deref() else {
        return MainChatStoreResponse::error("missing_text", "text is required");
    };
    let conversation = &mut snapshot.conversations[conversation_index];
    let message_index = if let Some(message_id) = request.message_id.as_deref() {
        assistant_target_index(conversation, Some(message_id))
    } else {
        assistant_target_index(conversation, None)
    };
    let Some(message_index) = message_index else {
        return MainChatStoreResponse::error("missing_message", "assistant message not found");
    };
    sync_primary_text_block(&mut conversation.messages[message_index], content);
    MainChatStoreResponse::success(snapshot)
}

pub fn sync_assistant_pipeline_state(
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
    let Some(pipeline_message) = request.message.as_ref() else {
        return MainChatStoreResponse::error("missing_message", "message payload is required");
    };
    let conversation = &mut snapshot.conversations[conversation_index];
    let Some(message_index) = assistant_target_index(conversation, Some(message_id)) else {
        return MainChatStoreResponse::error("missing_message", "assistant message not found");
    };

    let existing = conversation.messages[message_index].clone();
    let mut merged = pipeline_message.clone();
    let existing_primary = resolved_primary_text(&existing);
    let incoming_primary = resolved_primary_text(&merged);
    if incoming_primary.is_empty() && !existing_primary.is_empty() {
        sync_primary_text_block(&mut merged, &existing_primary);
    }
    if merged
        .reasoning_text
        .as_deref()
        .map(str::trim)
        .unwrap_or_default()
        .is_empty()
    {
        merged.reasoning_text = existing.reasoning_text.clone();
    }
    merged.blocks = merge_timeline_blocks(existing.blocks.as_ref(), merged.blocks.as_ref());
    if merged.subagent_cards.is_none() {
        merged.subagent_cards = existing.subagent_cards.clone();
    }
    normalize_message(&mut merged);
    merged.turn_metadata = pipeline_message.turn_metadata.clone();
    merged.reasoning_text = pipeline_message.reasoning_text.clone();
    if merged
        .reasoning_text
        .as_deref()
        .map(str::trim)
        .unwrap_or_default()
        .is_empty()
    {
        merged.reasoning_text = existing.reasoning_text.clone();
    }
    merged.is_streaming = pipeline_message.is_streaming;
    conversation.messages[message_index] = merged;
    MainChatStoreResponse::success(snapshot)
}

fn merge_timeline_blocks(
    existing: Option<&Vec<app_core_protocol::main_chat_store::MainChatStoreTimelineBlockSnapshot>>,
    incoming: Option<&Vec<app_core_protocol::main_chat_store::MainChatStoreTimelineBlockSnapshot>>,
) -> Option<Vec<app_core_protocol::main_chat_store::MainChatStoreTimelineBlockSnapshot>> {
    let existing_blocks = existing.cloned().unwrap_or_default();
    let incoming_blocks = incoming.cloned().unwrap_or_default();
    if incoming_blocks.is_empty() && existing_blocks.is_empty() {
        return None;
    }

    let select_core_group = |kind: &str| -> Vec<
        app_core_protocol::main_chat_store::MainChatStoreTimelineBlockSnapshot,
    > {
        let incoming_group: Vec<_> = incoming_blocks
            .iter()
            .filter(|block| block.kind == kind)
            .cloned()
            .collect();
        if !incoming_group.is_empty() {
            incoming_group
        } else {
            existing_blocks
                .iter()
                .filter(|block| block.kind == kind)
                .cloned()
                .collect()
        }
    };

    let mut merged_core = Vec::new();
    merged_core.extend(select_core_group("reasoning"));
    merged_core.extend(select_core_group("primaryText"));
    merged_core.extend(select_core_group("toolMarker"));
    merged_core.sort_by(|lhs, rhs| {
        lhs.sequence
            .cmp(&rhs.sequence)
            .then_with(|| {
                timeline_core_kind_priority(&lhs.kind).cmp(&timeline_core_kind_priority(&rhs.kind))
            })
            .then_with(|| lhs.id.cmp(&rhs.id))
    });

    let mut merged_other: Vec<_> = existing_blocks
        .into_iter()
        .filter(|block| !is_timeline_core_kind(&block.kind))
        .collect();
    for block in incoming_blocks
        .into_iter()
        .filter(|block| !is_timeline_core_kind(&block.kind))
    {
        if let Some(index) = merged_other
            .iter()
            .position(|candidate| candidate.id == block.id)
        {
            merged_other[index] = block;
        } else {
            merged_other.push(block);
        }
    }

    merged_core.extend(merged_other);
    (!merged_core.is_empty()).then_some(merged_core)
}

fn is_timeline_core_kind(kind: &str) -> bool {
    matches!(kind, "primaryText" | "reasoning" | "toolMarker")
}

fn timeline_core_kind_priority(kind: &str) -> u8 {
    match kind {
        "reasoning" => 0,
        "primaryText" => 1,
        "toolMarker" => 2,
        _ => 3,
    }
}

pub fn save_reasoning(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error(
            "missing_conversation_id",
            "conversationId is required",
        );
    };
    let Some(conversation_index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let conversation = &mut snapshot.conversations[conversation_index];
    let message_index = if let Some(message_id) = request.message_id.as_deref() {
        assistant_target_index(conversation, Some(message_id))
    } else {
        last_assistant_index(conversation)
    };
    let Some(message_index) = message_index else {
        return MainChatStoreResponse::error("missing_message", "assistant message not found");
    };
    if let Some(reasoning) = request.text.as_ref() {
        let cleaned =
            crate::main_chat::markers::strip_coderide_markers_wire(reasoning.trim(), true);
        if cleaned.is_empty() {
            conversation.messages[message_index].reasoning_text = None;
        } else {
            conversation.messages[message_index].reasoning_text = Some(cleaned);
        }
    }
    MainChatStoreResponse::success(snapshot)
}

pub fn save_subagent_cards_to_last_assistant(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error(
            "missing_conversation_id",
            "conversationId is required",
        );
    };
    let Some(conversation_index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let Some(cards) = request.subagent_cards.clone() else {
        return MainChatStoreResponse::error("missing_subagent_cards", "subagentCards is required");
    };
    if cards.is_empty() {
        return MainChatStoreResponse::success(snapshot);
    }

    let conversation = &mut snapshot.conversations[conversation_index];
    if let Some(message_index) = last_assistant_index(conversation) {
        conversation.messages[message_index].subagent_cards = Some(cards);
    } else {
        conversation.messages.push(MainChatStoreMessageSnapshot {
            id: format!("assistant-placeholder-{}", conversation.messages.len()),
            role: "assistant".to_string(),
            content: String::new(),
            primary_text_snapshot: Some(String::new()),
            blocks: None,
            turn_metadata: None,
            is_streaming: false,
            image_paths: None,
            attachments: None,
            plan_attachment: None,
            reasoning_text: None,
            subagent_cards: Some(cards),
        });
    }
    MainChatStoreResponse::success(snapshot)
}

pub fn set_streaming_state(
    mut snapshot: MainChatStoreSnapshot,
    request: &MainChatStoreActionRequest,
) -> MainChatStoreResponse {
    let Some(conversation_id) = request.conversation_id.as_deref() else {
        return MainChatStoreResponse::error(
            "missing_conversation_id",
            "conversationId is required",
        );
    };
    let Some(conversation_index) = conversation_index(&snapshot, conversation_id) else {
        return MainChatStoreResponse::error("missing_conversation", "conversation not found");
    };
    let conversation = &mut snapshot.conversations[conversation_index];
    let Some(message_index) = assistant_target_index(conversation, request.message_id.as_deref())
    else {
        return MainChatStoreResponse::error("missing_message", "assistant message not found");
    };
    conversation.messages[message_index].is_streaming = request.bool_value.unwrap_or(false);
    MainChatStoreResponse::success(snapshot)
}

pub fn remove_assistant_message_if_empty(
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
    let conversation = &mut snapshot.conversations[conversation_index];
    let Some(message_index) = conversation
        .messages
        .iter()
        .position(|item| item.id == message_id)
    else {
        return MainChatStoreResponse::error("missing_message", "message not found");
    };
    let message = &conversation.messages[message_index];
    let content = message
        .primary_text_snapshot
        .as_deref()
        .unwrap_or(message.content.as_str())
        .trim();
    if message.role == "assistant" && content.is_empty() {
        conversation.messages.remove(message_index);
    }
    MainChatStoreResponse::success(snapshot)
}
