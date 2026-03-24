use app_core_protocol::main_chat_store::{
    MainChatStoreConversationSnapshot, MainChatStoreMessageSnapshot,
    MainChatStoreTimelineBlockSnapshot,
};

pub fn assistant_target_index(
    conversation: &MainChatStoreConversationSnapshot,
    message_id: Option<&str>,
) -> Option<usize> {
    if let Some(message_id) = message_id {
        return conversation
            .messages
            .iter()
            .position(|item| item.id == message_id && item.role == "assistant");
    }

    conversation
        .messages
        .iter()
        .rposition(|item| item.role == "assistant" && item.is_streaming)
        .or_else(|| {
            conversation
                .messages
                .iter()
                .rposition(|item| item.role == "assistant")
        })
}

pub fn last_assistant_index(conversation: &MainChatStoreConversationSnapshot) -> Option<usize> {
    conversation
        .messages
        .iter()
        .rposition(|item| item.role == "assistant")
}

pub fn clear_stale_assistant_streaming(conversation: &mut MainChatStoreConversationSnapshot) {
    for message in conversation.messages.iter_mut() {
        if message.role == "assistant" {
            message.is_streaming = false;
        }
    }
}

pub fn update_new_conversation_title(
    conversation: &mut MainChatStoreConversationSnapshot,
    message: &MainChatStoreMessageSnapshot,
) {
    if conversation.title != "New conversation" || message.role != "user" {
        return;
    }

    let mut title = message.content.chars().take(40).collect::<String>();
    if message.content.chars().count() > 40 {
        title.push('…');
    }
    if !title.is_empty() {
        conversation.title = title;
    }
}

pub fn sync_primary_text_block(message: &mut MainChatStoreMessageSnapshot, content: &str) {
    message.content = content.to_string();
    message.primary_text_snapshot = Some(content.to_string());

    let blocks = message.blocks.get_or_insert_with(Vec::new);
    if let Some(index) = blocks.iter().position(|block| block.kind == "primaryText") {
        blocks[index].text = content.to_string();
    } else {
        blocks.insert(
            0,
            app_core_protocol::main_chat_store::MainChatStoreTimelineBlockSnapshot {
                id: "primary-text".to_string(),
                kind: "primaryText".to_string(),
                title: None,
                text: content.to_string(),
                items: Vec::new(),
                metadata: Default::default(),
                is_collapsible: false,
                is_collapsed_by_default: false,
                sequence: 0,
            },
        );
    }
}

pub fn resolved_primary_text(message: &MainChatStoreMessageSnapshot) -> String {
    let primary = message
        .primary_text_snapshot
        .as_deref()
        .unwrap_or_default()
        .trim()
        .to_string();
    if !primary.is_empty() {
        return primary;
    }
    message.content.trim().to_string()
}

pub fn sync_reasoning_block(message: &mut MainChatStoreMessageSnapshot, reasoning: &str) {
    let trimmed = reasoning.trim();
    if trimmed.is_empty() {
        return;
    }

    let blocks = message.blocks.get_or_insert_with(Vec::new);
    if let Some(index) = blocks.iter().position(|block| block.kind == "reasoning") {
        blocks[index].text = trimmed.to_string();
        blocks[index].title = Some("Thinking".to_string());
        blocks[index].is_collapsible = true;
        blocks[index].is_collapsed_by_default = true;
    } else {
        blocks.push(MainChatStoreTimelineBlockSnapshot {
            id: "reasoning".to_string(),
            kind: "reasoning".to_string(),
            title: Some("Thinking".to_string()),
            text: trimmed.to_string(),
            items: Vec::new(),
            metadata: Default::default(),
            is_collapsible: true,
            is_collapsed_by_default: true,
            sequence: 0,
        });
    }
}

pub fn normalize_message(message: &mut MainChatStoreMessageSnapshot) {
    let primary = resolved_primary_text(message);
    if !primary.is_empty() {
        sync_primary_text_block(message, &primary);
    }
    if let Some(reasoning) = message.reasoning_text.clone() {
        sync_reasoning_block(message, &reasoning);
    }
}
