use app_core_protocol::main_chat::{MainChatArtifact, MainChatArtifactKind, MainChatTurnState};
use app_core_protocol::main_chat_store::MainChatStoreTimelineBlockSnapshot;
use app_core_protocol::main_chat_ui::MainChatUiState;

pub fn sync_store_from_runtime(state: &mut MainChatUiState) {
    let Some(runtime_snapshot) = state.runtime_snapshot.as_ref() else {
        return;
    };
    let turn_state = &runtime_snapshot.turn_state;
    let Some(conversation) = state
        .store_snapshot
        .conversations
        .iter_mut()
        .find(|conversation| conversation.id == turn_state.conversation_id)
    else {
        return;
    };

    let target_index = conversation
        .messages
        .iter()
        .position(|message| message.id == turn_state.assistant_message_id)
        .or_else(|| conversation.messages.iter().rposition(|message| message.role == "assistant"));
    let Some(target_index) = target_index else { return };
    let message = &mut conversation.messages[target_index];
    message.content = resolved_message_content(turn_state);
    message.primary_text_snapshot = Some(turn_primary_text(turn_state));
    message.reasoning_text = reasoning_text(turn_state);
    message.turn_metadata = Some(app_core_protocol::main_chat_store::MainChatStoreTurnMetadataSnapshot {
        turn_id: turn_state.turn_id.clone(),
        provider_id: turn_state.provider_id.clone(),
        sequence: turn_state.sequence,
        status: turn_state.status.clone(),
        started_at: turn_state.started_at,
        completed_at: turn_state.completed_at,
        updated_at: turn_state.updated_at,
        is_streaming: turn_state.is_streaming,
    });
    message.is_streaming = turn_state.is_streaming;
    message.blocks = Some(runtime_blocks(turn_state));
}

pub fn mark_store_stream_finished(state: &mut MainChatUiState) {
    let Some(runtime_snapshot) = state.runtime_snapshot.as_ref() else {
        return;
    };
    let turn_state = &runtime_snapshot.turn_state;
    let Some(conversation) = state
        .store_snapshot
        .conversations
        .iter_mut()
        .find(|conversation| conversation.id == turn_state.conversation_id)
    else {
        return;
    };
    if let Some(message) = conversation
        .messages
        .iter_mut()
        .find(|message| message.id == turn_state.assistant_message_id)
    {
        message.is_streaming = false;
        if let Some(metadata) = message.turn_metadata.as_mut() {
            metadata.is_streaming = false;
            metadata.status = turn_state.status.clone();
            metadata.completed_at = turn_state.completed_at;
            metadata.updated_at = turn_state.updated_at;
        }
    }
}

fn resolved_message_content(turn_state: &MainChatTurnState) -> String {
    turn_primary_text(turn_state)
}

fn turn_primary_text(turn_state: &MainChatTurnState) -> String {
    let mut buffer = String::new();
    for stream_id in &turn_state.ordered_text_stream_ids {
        if let Some(text) = turn_state.text_by_stream_id.get(stream_id) {
            buffer.push_str(text);
        }
    }
    if buffer.is_empty() {
        if let Some(text) = turn_state.text_by_stream_id.get("main") {
            return text.clone();
        }
    }
    buffer
}

fn reasoning_text(turn_state: &MainChatTurnState) -> Option<String> {
    let combined = turn_state
        .reasoning_by_group_id
        .values()
        .filter(|value| !value.trim().is_empty())
        .cloned()
        .collect::<Vec<_>>()
        .join("\n\n");
    (!combined.is_empty()).then_some(combined)
}

fn runtime_blocks(turn_state: &MainChatTurnState) -> Vec<MainChatStoreTimelineBlockSnapshot> {
    let mut blocks = Vec::new();
    let primary_text = turn_primary_text(turn_state);
    if !primary_text.trim().is_empty() {
        blocks.push(MainChatStoreTimelineBlockSnapshot {
            id: "primary-text".to_string(),
            kind: "primaryText".to_string(),
            title: None,
            text: primary_text,
            items: Vec::new(),
            metadata: Default::default(),
            is_collapsible: false,
            is_collapsed_by_default: false,
        });
    }
    blocks.extend(turn_state.artifacts.iter().map(artifact_block));
    blocks
}

fn artifact_block(artifact: &MainChatArtifact) -> MainChatStoreTimelineBlockSnapshot {
    MainChatStoreTimelineBlockSnapshot {
        id: artifact.id.clone(),
        kind: artifact_kind(artifact.kind.clone()).to_string(),
        title: Some(artifact.title.clone()),
        text: artifact.text.clone(),
        items: artifact.items.clone(),
        metadata: artifact.metadata.clone(),
        is_collapsible: artifact.is_collapsible,
        is_collapsed_by_default: artifact.is_collapsed_by_default,
    }
}

fn artifact_kind(kind: MainChatArtifactKind) -> &'static str {
    match kind {
        MainChatArtifactKind::Mermaid => "mermaid",
        MainChatArtifactKind::Commands => "commands",
        MainChatArtifactKind::Files => "files",
        MainChatArtifactKind::Status => "status",
        MainChatArtifactKind::Plan => "plan",
        MainChatArtifactKind::ToolTrace => "toolTrace",
    }
}
