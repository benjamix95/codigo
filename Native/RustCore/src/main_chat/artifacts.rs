use app_core_protocol::main_chat::{
    MainChatArtifact, MainChatArtifactKind, MainChatEvent, MainChatTurnState,
};

pub fn stream_id(event: &MainChatEvent) -> String {
    event
        .payload
        .get("stream_id")
        .or_else(|| event.payload.get("task_id"))
        .or_else(|| event.payload.get("group_id"))
        .cloned()
        .unwrap_or_else(|| "main".to_string())
}

pub fn register_stream(state: &mut MainChatTurnState, stream_id: &str) {
    if !state
        .ordered_text_stream_ids
        .iter()
        .any(|value| value == stream_id)
    {
        state.ordered_text_stream_ids.push(stream_id.to_string());
    }
}

pub fn upsert_artifact(
    mut state: MainChatTurnState,
    artifact: MainChatArtifact,
) -> MainChatTurnState {
    if let Some(index) = state
        .artifacts
        .iter()
        .position(|candidate| candidate.id == artifact.id)
    {
        state.artifacts[index] = artifact;
    } else {
        state.artifacts.push(artifact);
    }
    state
}

pub fn append_item_artifact(
    state: MainChatTurnState,
    id: String,
    kind: MainChatArtifactKind,
    title: String,
    item: String,
) -> MainChatTurnState {
    let mut artifact = state
        .artifacts
        .iter()
        .find(|candidate| candidate.id == id)
        .cloned()
        .unwrap_or(MainChatArtifact {
            id,
            kind,
            title,
            items: Vec::new(),
            is_collapsed_by_default: true,
            ..Default::default()
        });
    if !artifact.items.iter().any(|candidate| candidate == &item) {
        artifact.items.push(item);
    }
    upsert_artifact(state, artifact)
}

pub fn upsert_status_artifact(
    state: MainChatTurnState,
    id: String,
    title: String,
    text: String,
) -> MainChatTurnState {
    upsert_artifact(
        state,
        MainChatArtifact {
            id,
            kind: MainChatArtifactKind::Status,
            title,
            text,
            is_collapsed_by_default: false,
            ..Default::default()
        },
    )
}

pub fn merge_reasoning_text(existing: Option<String>, incoming: String) -> String {
    let incoming_trimmed = incoming.trim().to_string();
    if incoming_trimmed.is_empty() {
        return existing.unwrap_or_default();
    }
    match existing {
        None => incoming_trimmed,
        Some(current) if current.is_empty() => incoming_trimmed,
        Some(current) if current == incoming_trimmed || current.contains(&incoming_trimmed) => {
            current
        }
        Some(current)
            if incoming_trimmed.starts_with(&current) || incoming_trimmed.contains(&current) =>
        {
            incoming_trimmed
        }
        Some(current) => format!("{current}\n\n{incoming_trimmed}"),
    }
}
