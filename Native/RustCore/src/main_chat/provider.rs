use crate::main_chat::apply_event;
use app_core_protocol::main_chat::{
    MainChatEvent, MainChatEventKind, MainChatProviderChunkKind, MainChatProviderStreamRequest,
    MainChatRuntimeResponse,
};

pub fn bridge_provider_stream(request: MainChatProviderStreamRequest) -> MainChatRuntimeResponse {
    if request.schema_version != 1 {
        return MainChatRuntimeResponse::error("unsupported_schema", "schemaVersion must be 1");
    }
    let mut state = request.state;
    let mut emitted_events = Vec::new();
    for (offset, chunk) in request.chunks.into_iter().enumerate() {
        let event = MainChatEvent {
            id: format!("{}:chunk-{}", state.turn_id, offset),
            conversation_id: state.conversation_id.clone(),
            assistant_message_id: state.assistant_message_id.clone(),
            turn_id: state.turn_id.clone(),
            sequence: state.sequence + offset as i32 + 1,
            source: request.source.clone(),
            kind: map_chunk_kind(&chunk.kind),
            payload: chunk.payload,
            timestamp: chunk
                .timestamp
                .unwrap_or_else(|| state.updated_at.unwrap_or(0.0)),
        };
        state = apply_event(state, &event);
        emitted_events.push(event);
    }
    MainChatRuntimeResponse::success_with_events(state, emitted_events)
}

fn map_chunk_kind(kind: &MainChatProviderChunkKind) -> MainChatEventKind {
    match kind {
        MainChatProviderChunkKind::Started => MainChatEventKind::TurnStarted,
        MainChatProviderChunkKind::TextDelta => MainChatEventKind::TextDelta,
        MainChatProviderChunkKind::TextReplace => MainChatEventKind::TextReplace,
        MainChatProviderChunkKind::Completed => MainChatEventKind::TurnCompleted,
        MainChatProviderChunkKind::Error => MainChatEventKind::TurnFailed,
        MainChatProviderChunkKind::ReasoningDelta => MainChatEventKind::ReasoningDelta,
        MainChatProviderChunkKind::MermaidArtifact => MainChatEventKind::MermaidArtifact,
        MainChatProviderChunkKind::ToolTraceArtifact => MainChatEventKind::ToolTraceArtifact,
        MainChatProviderChunkKind::CommandsArtifact => MainChatEventKind::CommandsArtifact,
        MainChatProviderChunkKind::FilesArtifact => MainChatEventKind::FilesArtifact,
        MainChatProviderChunkKind::StatusBadge => MainChatEventKind::StatusBadge,
        MainChatProviderChunkKind::PlanArtifact => MainChatEventKind::PlanArtifact,
    }
}

#[cfg(test)]
mod tests {
    use super::bridge_provider_stream;
    use app_core_protocol::main_chat::{
        MainChatProviderChunk, MainChatProviderChunkKind, MainChatProviderStreamRequest,
        MainChatTurnState,
    };
    use std::collections::BTreeMap;

    #[test]
    fn provider_stream_maps_chunks_into_events_and_state() {
        let response = bridge_provider_stream(MainChatProviderStreamRequest {
            schema_version: 1,
            state: MainChatTurnState {
                conversation_id: "conv".to_string(),
                assistant_message_id: "msg".to_string(),
                turn_id: "turn".to_string(),
                status: "idle".to_string(),
                ..Default::default()
            },
            source: "codex".to_string(),
            chunks: vec![
                chunk(
                    MainChatProviderChunkKind::Started,
                    &[("status", "streaming")],
                ),
                chunk(
                    MainChatProviderChunkKind::TextDelta,
                    &[("stream_id", "main"), ("delta", "ciao")],
                ),
                chunk(
                    MainChatProviderChunkKind::Completed,
                    &[("status", "completed")],
                ),
            ],
        });
        let state = response.state.expect("state");
        assert_eq!(response.emitted_events.len(), 3);
        assert_eq!(
            state.text_by_stream_id.get("main").map(String::as_str),
            Some("ciao")
        );
        assert_eq!(state.status, "completed");
    }

    fn chunk(kind: MainChatProviderChunkKind, values: &[(&str, &str)]) -> MainChatProviderChunk {
        MainChatProviderChunk {
            kind,
            payload: values
                .iter()
                .map(|(key, value)| ((*key).to_string(), (*value).to_string()))
                .collect::<BTreeMap<_, _>>(),
            timestamp: Some(1.0),
        }
    }
}
