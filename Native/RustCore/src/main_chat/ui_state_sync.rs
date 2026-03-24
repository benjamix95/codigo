use app_core_protocol::main_chat::{
    MainChatArtifact, MainChatArtifactKind, MainChatTurnState, TimelineSegmentKind,
};
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
        .position(|message| message.id == turn_state.assistant_message_id);
    let Some(target_index) = target_index else {
        return;
    };
    let message = &mut conversation.messages[target_index];
    message.content = resolved_message_content(turn_state);
    message.primary_text_snapshot = Some(turn_primary_text(turn_state));
    message.reasoning_text = reasoning_text(turn_state);
    message.turn_metadata = Some(
        app_core_protocol::main_chat_store::MainChatStoreTurnMetadataSnapshot {
            turn_id: turn_state.turn_id.clone(),
            provider_id: turn_state.provider_id.clone(),
            sequence: turn_state.sequence,
            status: turn_state.status.clone(),
            started_at: turn_state.started_at,
            completed_at: turn_state.completed_at,
            updated_at: turn_state.updated_at,
            is_streaming: turn_state.is_streaming,
        },
    );
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

pub fn apply_terminal_text_override(state: &mut MainChatUiState, text: &str) {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return;
    }
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
        let value = text.to_string();
        message.content = value.clone();
        message.primary_text_snapshot = Some(value.clone());
        if let Some(blocks) = message.blocks.as_mut() {
            if let Some(primary_block) = blocks.iter_mut().find(|block| block.kind == "primaryText")
            {
                primary_block.text = value;
            }
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

    // If we have interleaved timeline segments, emit multiple text blocks
    // with proper sequence numbers so Swift can interleave them with tool
    // trace events.
    if !turn_state.timeline_segments.is_empty() {
        let reasoning = reasoning_text(turn_state);
        for seg in &turn_state.timeline_segments {
            match seg.kind {
                TimelineSegmentKind::Text => {
                    if let Some(text) = turn_state.text_segments.get(seg.index) {
                        if !text.trim().is_empty() {
                            blocks.push(MainChatStoreTimelineBlockSnapshot {
                                id: format!("text-seg-{}", seg.index),
                                kind: "primaryText".to_string(),
                                title: None,
                                text: text.clone(),
                                items: Vec::new(),
                                metadata: Default::default(),
                                is_collapsible: false,
                                is_collapsed_by_default: false,
                                sequence: seg.sequence,
                            });
                        }
                    }
                }
                TimelineSegmentKind::Reasoning => {
                    if let Some(ref r) = reasoning {
                        blocks.push(MainChatStoreTimelineBlockSnapshot {
                            id: "reasoning".to_string(),
                            kind: "reasoning".to_string(),
                            title: Some("Thinking".to_string()),
                            text: r.clone(),
                            items: Vec::new(),
                            metadata: Default::default(),
                            is_collapsible: true,
                            is_collapsed_by_default: true,
                            sequence: seg.sequence,
                        });
                    }
                }
                TimelineSegmentKind::ToolUse => {
                    // ToolUse segments are placeholders — the actual tool
                    // trace events are rendered by Swift's ToolTraceStore.
                    // We emit a marker block so Swift knows the sequence.
                    blocks.push(MainChatStoreTimelineBlockSnapshot {
                        id: format!("tool-marker-{}", seg.sequence),
                        kind: "toolMarker".to_string(),
                        title: None,
                        text: String::new(),
                        items: Vec::new(),
                        metadata: Default::default(),
                        is_collapsible: false,
                        is_collapsed_by_default: false,
                        sequence: seg.sequence,
                    });
                }
            }
        }
    } else {
        // Fallback: no timeline segments (e.g. non-streaming or old data).
        // Emit single blocks like before.
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
                sequence: 0,
            });
        }
        if let Some(reasoning) = reasoning_text(turn_state) {
            blocks.push(MainChatStoreTimelineBlockSnapshot {
                id: "reasoning".to_string(),
                kind: "reasoning".to_string(),
                title: Some("Thinking".to_string()),
                text: reasoning,
                items: Vec::new(),
                metadata: Default::default(),
                is_collapsible: true,
                is_collapsed_by_default: true,
                sequence: 0,
            });
        }
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
        sequence: 0,
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

#[cfg(test)]
mod tests {
    use super::runtime_blocks;
    use app_core_protocol::main_chat::{MainChatTurnState, TimelineSegment, TimelineSegmentKind};

    fn base_state() -> MainChatTurnState {
        MainChatTurnState {
            conversation_id: "conv".to_string(),
            assistant_message_id: "msg".to_string(),
            turn_id: "turn".to_string(),
            status: "streaming".to_string(),
            ..Default::default()
        }
    }

    #[test]
    fn runtime_blocks_with_segments_emits_multiple_text_blocks() {
        let mut state = base_state();
        state.text_segments = vec!["First text".to_string(), "Second text".to_string()];
        state.timeline_segments = vec![
            TimelineSegment {
                kind: TimelineSegmentKind::Text,
                index: 0,
                sequence: 0,
            },
            TimelineSegment {
                kind: TimelineSegmentKind::ToolUse,
                index: 0,
                sequence: 1,
            },
            TimelineSegment {
                kind: TimelineSegmentKind::Text,
                index: 1,
                sequence: 2,
            },
        ];
        let blocks = runtime_blocks(&state);
        let text_blocks: Vec<_> = blocks.iter().filter(|b| b.kind == "primaryText").collect();
        assert_eq!(text_blocks.len(), 2);
        assert_eq!(text_blocks[0].text, "First text");
        assert_eq!(text_blocks[0].sequence, 0);
        assert_eq!(text_blocks[1].text, "Second text");
        assert_eq!(text_blocks[1].sequence, 2);
    }

    #[test]
    fn runtime_blocks_with_segments_emits_tool_markers() {
        let mut state = base_state();
        state.text_segments = vec!["Hello".to_string()];
        state.timeline_segments = vec![
            TimelineSegment {
                kind: TimelineSegmentKind::Text,
                index: 0,
                sequence: 0,
            },
            TimelineSegment {
                kind: TimelineSegmentKind::ToolUse,
                index: 0,
                sequence: 1,
            },
        ];
        let blocks = runtime_blocks(&state);
        let markers: Vec<_> = blocks.iter().filter(|b| b.kind == "toolMarker").collect();
        assert_eq!(markers.len(), 1);
        assert_eq!(markers[0].sequence, 1);
    }

    #[test]
    fn runtime_blocks_with_reasoning_segment() {
        let mut state = base_state();
        state
            .reasoning_by_group_id
            .insert("reasoning".to_string(), "Thinking hard".to_string());
        state.text_segments = vec!["Answer".to_string()];
        state.timeline_segments = vec![
            TimelineSegment {
                kind: TimelineSegmentKind::Reasoning,
                index: 0,
                sequence: 0,
            },
            TimelineSegment {
                kind: TimelineSegmentKind::Text,
                index: 0,
                sequence: 1,
            },
        ];
        let blocks = runtime_blocks(&state);
        assert_eq!(blocks.len(), 2);
        assert_eq!(blocks[0].kind, "reasoning");
        assert_eq!(blocks[0].sequence, 0);
        assert_eq!(blocks[1].kind, "primaryText");
        assert_eq!(blocks[1].sequence, 1);
    }

    #[test]
    fn runtime_blocks_fallback_when_no_segments() {
        let mut state = base_state();
        state
            .text_by_stream_id
            .insert("main".to_string(), "Single text".to_string());
        state.ordered_text_stream_ids.push("main".to_string());
        // No timeline_segments
        let blocks = runtime_blocks(&state);
        let text_blocks: Vec<_> = blocks.iter().filter(|b| b.kind == "primaryText").collect();
        assert_eq!(text_blocks.len(), 1);
        assert_eq!(text_blocks[0].text, "Single text");
        assert_eq!(text_blocks[0].sequence, 0);
    }

    #[test]
    fn runtime_blocks_skips_empty_text_segments() {
        let mut state = base_state();
        state.text_segments = vec!["  ".to_string(), "Real text".to_string()];
        state.timeline_segments = vec![
            TimelineSegment {
                kind: TimelineSegmentKind::Text,
                index: 0,
                sequence: 0,
            },
            TimelineSegment {
                kind: TimelineSegmentKind::ToolUse,
                index: 0,
                sequence: 1,
            },
            TimelineSegment {
                kind: TimelineSegmentKind::Text,
                index: 1,
                sequence: 2,
            },
        ];
        let blocks = runtime_blocks(&state);
        let text_blocks: Vec<_> = blocks.iter().filter(|b| b.kind == "primaryText").collect();
        assert_eq!(text_blocks.len(), 1);
        assert_eq!(text_blocks[0].text, "Real text");
    }
}
