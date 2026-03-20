use crate::main_chat::artifacts::{
    append_item_artifact, merge_reasoning_text, register_stream, stream_id, upsert_artifact,
    upsert_status_artifact,
};
use app_core_protocol::main_chat::{
    MainChatArtifact, MainChatArtifactKind, MainChatEvent, MainChatEventKind, MainChatTurnState,
};

pub fn apply_event(state: MainChatTurnState, event: &MainChatEvent) -> MainChatTurnState {
    let mut next = state;
    next.sequence = next.sequence.max(event.sequence);
    next.updated_at = Some(event.timestamp);
    if next.provider_id.is_none() {
        next.provider_id = event
            .payload
            .get("provider_id")
            .cloned()
            .or_else(|| Some(event.source.clone()));
    }

    match event.kind {
        MainChatEventKind::TurnStarted => {
            next.is_streaming = true;
            next.status = event
                .payload
                .get("status")
                .cloned()
                .unwrap_or_else(|| "streaming".to_string());
            if next.started_at.is_none() {
                next.started_at = Some(event.timestamp);
            }
        }
        MainChatEventKind::TurnCompleted => {
            next.is_streaming = false;
            next.status = event
                .payload
                .get("status")
                .cloned()
                .unwrap_or_else(|| "completed".to_string());
            next.completed_at = Some(event.timestamp);
        }
        MainChatEventKind::TurnFailed => {
            next.is_streaming = false;
            next.status = event
                .payload
                .get("status")
                .cloned()
                .unwrap_or_else(|| "failed".to_string());
            next.completed_at = Some(event.timestamp);
            next = upsert_status_artifact(
                next,
                "turn-failed".to_string(),
                "Turn failed".to_string(),
                event.payload
                    .get("detail")
                    .cloned()
                    .or_else(|| event.payload.get("error").cloned())
                    .unwrap_or_else(|| "Unexpected error".to_string()),
            );
        }
        MainChatEventKind::TextDelta => {
            let stream_id = stream_id(event);
            register_stream(&mut next, &stream_id);
            next.text_by_stream_id
                .entry(stream_id)
                .and_modify(|text| text.push_str(event.payload.get("delta").map(String::as_str).unwrap_or_default()))
                .or_insert_with(|| event.payload.get("delta").cloned().unwrap_or_default());
        }
        MainChatEventKind::TextReplace => {
            let stream_id = stream_id(event);
            register_stream(&mut next, &stream_id);
            next.text_by_stream_id.insert(
                stream_id,
                event.payload.get("replacement").cloned().unwrap_or_default(),
            );
        }
        MainChatEventKind::ReasoningDelta => {
            let group_id = event
                .payload
                .get("group_id")
                .cloned()
                .unwrap_or_else(|| "reasoning".to_string());
            let merged = merge_reasoning_text(
                next.reasoning_by_group_id.get(&group_id).cloned(),
                event.payload.get("output").cloned().unwrap_or_default(),
            );
            if !merged.is_empty() {
                next.reasoning_by_group_id.insert(group_id, merged);
            }
        }
        MainChatEventKind::MermaidArtifact => {
            if let Some(code) = event.payload.get("code").cloned().filter(|value| !value.is_empty()) {
                let next_artifact_id = event
                    .payload
                    .get("artifact_id")
                    .cloned()
                    .unwrap_or_else(|| format!("mermaid-{}", next.artifacts.len()));
                next = upsert_artifact(
                    next,
                    MainChatArtifact {
                        id: next_artifact_id,
                        kind: MainChatArtifactKind::Mermaid,
                        title: event
                            .payload
                            .get("title")
                            .cloned()
                            .unwrap_or_else(|| "Diagram".to_string()),
                        text: code,
                        ..Default::default()
                    },
                );
            }
        }
        MainChatEventKind::CommandsArtifact => {
            if let Some(item) = event.payload.get("command").cloned().filter(|value| !value.is_empty()) {
                next = append_item_artifact(
                    next,
                    "commands".to_string(),
                    MainChatArtifactKind::Commands,
                    "Commands executed".to_string(),
                    item,
                );
            }
        }
        MainChatEventKind::FilesArtifact => {
            if let Some(item) = event.payload.get("path").cloned().filter(|value| !value.is_empty()) {
                next = append_item_artifact(
                    next,
                    "files".to_string(),
                    MainChatArtifactKind::Files,
                    "Files touched".to_string(),
                    item,
                );
            }
        }
        MainChatEventKind::StatusBadge => {
            let text = event
                .payload
                .get("detail")
                .cloned()
                .or_else(|| event.payload.get("status").cloned())
                .unwrap_or_default();
            if !text.is_empty() {
                next = upsert_status_artifact(
                    next,
                    event
                        .payload
                        .get("artifact_id")
                        .cloned()
                        .unwrap_or_else(|| event.payload.get("title").cloned().unwrap_or_else(|| "Status".to_string())),
                    event
                        .payload
                        .get("title")
                        .cloned()
                        .unwrap_or_else(|| "Status".to_string()),
                    text,
                );
            }
        }
        MainChatEventKind::PlanArtifact => {
            if let Some(text) = event.payload.get("text").cloned().filter(|value| !value.is_empty()) {
                let next_artifact_id = event
                    .payload
                    .get("artifact_id")
                    .cloned()
                    .unwrap_or_else(|| format!("plan-{}", next.artifacts.len()));
                next = upsert_artifact(
                    next,
                    MainChatArtifact {
                        id: next_artifact_id,
                        kind: MainChatArtifactKind::Plan,
                        title: event
                            .payload
                            .get("title")
                            .cloned()
                            .unwrap_or_else(|| "Plan".to_string()),
                        text,
                        ..Default::default()
                    },
                );
            }
        }
        MainChatEventKind::ToolTraceArtifact => {
            if let Some(text) = event.payload.get("detail").cloned().filter(|value| !value.is_empty()) {
                next = upsert_artifact(
                    next,
                    MainChatArtifact {
                        id: event
                            .payload
                            .get("artifact_id")
                            .cloned()
                            .unwrap_or_else(|| "tool-trace".to_string()),
                        kind: MainChatArtifactKind::ToolTrace,
                        title: event
                            .payload
                            .get("title")
                            .cloned()
                            .unwrap_or_else(|| "Trace summary".to_string()),
                        text,
                        is_collapsed_by_default: true,
                        ..Default::default()
                    },
                );
            }
        }
        MainChatEventKind::TodoSnapshot => {}
    }

    next
}

#[cfg(test)]
mod tests {
    use super::apply_event;
    use app_core_protocol::main_chat::{MainChatEvent, MainChatEventKind, MainChatTurnState};
    use std::collections::BTreeMap;

    #[test]
    fn keeps_primary_text_order_stable_across_stream_ids() {
        let mut state = MainChatTurnState {
            conversation_id: "conv".to_string(),
            assistant_message_id: "msg".to_string(),
            turn_id: "turn".to_string(),
            status: "idle".to_string(),
            ordered_text_stream_ids: vec!["task-1".to_string(), "task-2".to_string()],
            ..Default::default()
        };
        state = apply_event(state, &event(1, MainChatEventKind::TextDelta, map(&[("stream_id", "task-2"), ("delta", "second")])));
        state = apply_event(state, &event(2, MainChatEventKind::TextDelta, map(&[("stream_id", "task-1"), ("delta", "first ")])));
        let joined = state
            .ordered_text_stream_ids
            .iter()
            .filter_map(|stream_id| state.text_by_stream_id.get(stream_id))
            .cloned()
            .collect::<Vec<_>>()
            .join("");
        assert_eq!(joined.trim(), "first second");
    }

    #[test]
    fn keeps_mermaid_as_artifact() {
        let state = MainChatTurnState {
            conversation_id: "conv".to_string(),
            assistant_message_id: "msg".to_string(),
            turn_id: "turn".to_string(),
            status: "idle".to_string(),
            ..Default::default()
        };
        let state = apply_event(state, &event(1, MainChatEventKind::TextReplace, map(&[("replacement", "Primary response"), ("stream_id", "main")])));
        let state = apply_event(state, &event(2, MainChatEventKind::MermaidArtifact, map(&[("artifact_id", "mermaid-1"), ("title", "Flow"), ("code", "graph TD; A-->B;")])));
        assert_eq!(state.text_by_stream_id.get("main").map(String::as_str), Some("Primary response"));
        assert!(state.artifacts.iter().any(|artifact| artifact.kind == app_core_protocol::main_chat::MainChatArtifactKind::Mermaid));
    }

    fn event(sequence: i32, kind: MainChatEventKind, payload: BTreeMap<String, String>) -> MainChatEvent {
        MainChatEvent {
            id: format!("event-{sequence}"),
            conversation_id: "conv".to_string(),
            assistant_message_id: "msg".to_string(),
            turn_id: "turn".to_string(),
            sequence,
            source: "test".to_string(),
            kind,
            payload,
            timestamp: sequence as f64,
        }
    }

    fn map(values: &[(&str, &str)]) -> BTreeMap<String, String> {
        values
            .iter()
            .map(|(key, value)| ((*key).to_string(), (*value).to_string()))
            .collect()
    }
}
