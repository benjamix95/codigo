use crate::main_chat::artifacts::{
    append_item_artifact, merge_reasoning_text, register_stream, stream_id, upsert_artifact,
    upsert_status_artifact,
};
use app_core_protocol::main_chat::{
    MainChatArtifact, MainChatArtifactKind, MainChatEvent, MainChatEventKind, MainChatTurnState,
    TimelineSegment, TimelineSegmentKind,
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
            let delta = event.payload.get("delta").map(String::as_str).unwrap_or_default();
            next.text_by_stream_id
                .entry(stream_id)
                .and_modify(|text| text.push_str(delta))
                .or_insert_with(|| delta.to_string());
            // Track interleaved timeline: append to current text segment
            // or start a new one if last segment wasn't text.
            ensure_text_segment(&mut next);
            if let Some(seg_idx) = current_text_segment_index(&next) {
                if seg_idx < next.text_segments.len() {
                    next.text_segments[seg_idx].push_str(delta);
                }
            }
        }
        MainChatEventKind::TextReplace => {
            let stream_id = stream_id(event);
            register_stream(&mut next, &stream_id);
            let replacement = event.payload.get("replacement").cloned().unwrap_or_default();
            next.text_by_stream_id.insert(
                stream_id,
                replacement.clone(),
            );
            // Track interleaved timeline
            ensure_text_segment(&mut next);
            if let Some(seg_idx) = current_text_segment_index(&next) {
                if seg_idx < next.text_segments.len() {
                    next.text_segments[seg_idx] = replacement;
                }
            }
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
            // Track reasoning segment if last segment wasn't reasoning
            ensure_reasoning_segment(&mut next);
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
        // CommandsArtifact and FilesArtifact are handled by the combined
        // CommandsArtifact | FilesArtifact arm above.
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
        MainChatEventKind::CommandsArtifact | MainChatEventKind::FilesArtifact => {
            // These are tool-like events; handled below but also record
            // a ToolUse timeline segment so text interleaves correctly.
            ensure_tool_segment(&mut next);
            // Fall through to matching below won't work in Rust,
            // so we duplicate the original handling inline.
            match event.kind {
                MainChatEventKind::CommandsArtifact => {
                    if let Some(item) = event.payload.get("command").cloned().filter(|v| !v.is_empty()) {
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
                    if let Some(item) = event.payload.get("path").cloned().filter(|v| !v.is_empty()) {
                        next = append_item_artifact(
                            next,
                            "files".to_string(),
                            MainChatArtifactKind::Files,
                            "Files touched".to_string(),
                            item,
                        );
                    }
                }
                _ => {}
            }
        }
        MainChatEventKind::ToolTraceArtifact => {
            ensure_tool_segment(&mut next);
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

// ─── Timeline Segment Helpers ────────────────────────────────────────────────

/// Ensures the last timeline segment is of kind `Text`.
/// If it isn't (or timeline is empty), pushes a new text segment
/// and a corresponding empty entry in `text_segments`.
fn ensure_text_segment(state: &mut MainChatTurnState) {
    let is_last_text = state
        .timeline_segments
        .last()
        .map_or(false, |s| s.kind == TimelineSegmentKind::Text);
    if !is_last_text {
        let idx = state.text_segments.len();
        state.text_segments.push(String::new());
        let seq = state.timeline_next_sequence;
        state.timeline_next_sequence += 1;
        state.timeline_segments.push(TimelineSegment {
            kind: TimelineSegmentKind::Text,
            index: idx,
            sequence: seq,
        });
    }
}

/// Returns the `text_segments` index for the current (last) text segment.
fn current_text_segment_index(state: &MainChatTurnState) -> Option<usize> {
    state
        .timeline_segments
        .iter()
        .rev()
        .find(|s| s.kind == TimelineSegmentKind::Text)
        .map(|s| s.index)
}

/// Ensures the last timeline segment is of kind `Reasoning`.
fn ensure_reasoning_segment(state: &mut MainChatTurnState) {
    let is_last_reasoning = state
        .timeline_segments
        .last()
        .map_or(false, |s| s.kind == TimelineSegmentKind::Reasoning);
    if !is_last_reasoning {
        let seq = state.timeline_next_sequence;
        state.timeline_next_sequence += 1;
        state.timeline_segments.push(TimelineSegment {
            kind: TimelineSegmentKind::Reasoning,
            index: 0,
            sequence: seq,
        });
    }
}

/// Ensures the last timeline segment is of kind `ToolUse`.
fn ensure_tool_segment(state: &mut MainChatTurnState) {
    let is_last_tool = state
        .timeline_segments
        .last()
        .map_or(false, |s| s.kind == TimelineSegmentKind::ToolUse);
    if !is_last_tool {
        let seq = state.timeline_next_sequence;
        state.timeline_next_sequence += 1;
        state.timeline_segments.push(TimelineSegment {
            kind: TimelineSegmentKind::ToolUse,
            index: 0,
            sequence: seq,
        });
    }
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

    fn base_state() -> MainChatTurnState {
        MainChatTurnState {
            conversation_id: "conv".to_string(),
            assistant_message_id: "msg".to_string(),
            turn_id: "turn".to_string(),
            status: "streaming".to_string(),
            ..Default::default()
        }
    }

    // ── Timeline Segment Tests ───────────────────────────────────────

    #[test]
    fn text_delta_creates_first_text_segment() {
        let state = base_state();
        let state = apply_event(state, &event(1, MainChatEventKind::TextDelta, map(&[("delta", "Hello")])));
        assert_eq!(state.text_segments.len(), 1);
        assert_eq!(state.text_segments[0], "Hello");
        assert_eq!(state.timeline_segments.len(), 1);
        assert_eq!(state.timeline_segments[0].kind, app_core_protocol::main_chat::TimelineSegmentKind::Text);
        assert_eq!(state.timeline_segments[0].sequence, 0);
    }

    #[test]
    fn consecutive_text_deltas_accumulate_in_same_segment() {
        let state = base_state();
        let state = apply_event(state, &event(1, MainChatEventKind::TextDelta, map(&[("delta", "Hello")])));
        let state = apply_event(state, &event(2, MainChatEventKind::TextDelta, map(&[("delta", " World")])));
        assert_eq!(state.text_segments.len(), 1);
        assert_eq!(state.text_segments[0], "Hello World");
        assert_eq!(state.timeline_segments.len(), 1);
    }

    #[test]
    fn tool_after_text_creates_new_segment() {
        let state = base_state();
        let state = apply_event(state, &event(1, MainChatEventKind::TextDelta, map(&[("delta", "Analyzing...")])));
        let state = apply_event(state, &event(2, MainChatEventKind::ToolTraceArtifact, map(&[("detail", "Ran grep"), ("title", "Trace")])));
        assert_eq!(state.timeline_segments.len(), 2);
        assert_eq!(state.timeline_segments[0].kind, app_core_protocol::main_chat::TimelineSegmentKind::Text);
        assert_eq!(state.timeline_segments[1].kind, app_core_protocol::main_chat::TimelineSegmentKind::ToolUse);
        assert_eq!(state.timeline_segments[0].sequence, 0);
        assert_eq!(state.timeline_segments[1].sequence, 1);
    }

    #[test]
    fn text_after_tool_creates_new_text_segment() {
        let state = base_state();
        let state = apply_event(state, &event(1, MainChatEventKind::TextDelta, map(&[("delta", "First")])));
        let state = apply_event(state, &event(2, MainChatEventKind::CommandsArtifact, map(&[("command", "ls -la")])));
        let state = apply_event(state, &event(3, MainChatEventKind::TextDelta, map(&[("delta", "Second")])));
        assert_eq!(state.text_segments.len(), 2);
        assert_eq!(state.text_segments[0], "First");
        assert_eq!(state.text_segments[1], "Second");
        assert_eq!(state.timeline_segments.len(), 3);
        assert_eq!(state.timeline_segments[0].sequence, 0); // text
        assert_eq!(state.timeline_segments[1].sequence, 1); // tool
        assert_eq!(state.timeline_segments[2].sequence, 2); // text
    }

    #[test]
    fn reasoning_creates_reasoning_segment() {
        let state = base_state();
        let state = apply_event(state, &event(1, MainChatEventKind::TextDelta, map(&[("delta", "Hello")])));
        let state = apply_event(state, &event(2, MainChatEventKind::ReasoningDelta, map(&[("output", "Thinking...")])));
        assert_eq!(state.timeline_segments.len(), 2);
        assert_eq!(state.timeline_segments[1].kind, app_core_protocol::main_chat::TimelineSegmentKind::Reasoning);
    }

    #[test]
    fn full_interleaved_sequence_text_tool_text_tool_text() {
        let state = base_state();
        let state = apply_event(state, &event(1, MainChatEventKind::TextDelta, map(&[("delta", "Analyzing project")])));
        let state = apply_event(state, &event(2, MainChatEventKind::CommandsArtifact, map(&[("command", "grep -r TODO")])));
        let state = apply_event(state, &event(3, MainChatEventKind::TextDelta, map(&[("delta", "Found issues")])));
        let state = apply_event(state, &event(4, MainChatEventKind::FilesArtifact, map(&[("path", "src/main.rs")])));
        let state = apply_event(state, &event(5, MainChatEventKind::TextDelta, map(&[("delta", "Fixed all")])));

        assert_eq!(state.text_segments.len(), 3);
        assert_eq!(state.text_segments[0], "Analyzing project");
        assert_eq!(state.text_segments[1], "Found issues");
        assert_eq!(state.text_segments[2], "Fixed all");

        assert_eq!(state.timeline_segments.len(), 5);
        // Verify sequence is monotonically increasing
        for i in 1..state.timeline_segments.len() {
            assert!(state.timeline_segments[i].sequence > state.timeline_segments[i - 1].sequence);
        }
        assert_eq!(state.timeline_next_sequence, 5);
    }

    #[test]
    fn consecutive_tools_reuse_same_tool_segment() {
        let state = base_state();
        let state = apply_event(state, &event(1, MainChatEventKind::CommandsArtifact, map(&[("command", "ls")])));
        let state = apply_event(state, &event(2, MainChatEventKind::FilesArtifact, map(&[("path", "a.rs")])));
        // Both tool events should go into one ToolUse segment
        assert_eq!(state.timeline_segments.len(), 1);
        assert_eq!(state.timeline_segments[0].kind, app_core_protocol::main_chat::TimelineSegmentKind::ToolUse);
    }

    #[test]
    fn text_replace_creates_or_updates_segment() {
        let state = base_state();
        let state = apply_event(state, &event(1, MainChatEventKind::TextReplace, map(&[("replacement", "Replaced text"), ("stream_id", "main")])));
        assert_eq!(state.text_segments.len(), 1);
        assert_eq!(state.text_segments[0], "Replaced text");
    }
}
