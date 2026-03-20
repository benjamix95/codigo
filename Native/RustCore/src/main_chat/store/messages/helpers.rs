use app_core_protocol::main_chat_store::{
    MainChatStoreConversationSnapshot, MainChatStoreMessageSnapshot,
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
        .or_else(|| conversation.messages.iter().rposition(|item| item.role == "assistant"))
}

pub fn last_assistant_index(conversation: &MainChatStoreConversationSnapshot) -> Option<usize> {
    conversation.messages.iter().rposition(|item| item.role == "assistant")
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
            },
        );
    }
}
