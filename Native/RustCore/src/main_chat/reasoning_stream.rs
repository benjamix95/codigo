use app_core_protocol::main_chat_reasoning::{
    MainChatReasoningBlock, MainChatReasoningRequest, MainChatReasoningResponse,
    MainChatReasoningSegment, MainChatReasoningState,
};

pub fn handle_reasoning_request(request: MainChatReasoningRequest) -> MainChatReasoningResponse {
    if request.schema_version != 1 {
        return MainChatReasoningResponse::error(
            "unsupported_schema",
            "schemaVersion must be 1",
        );
    }
    match request.operation.as_str() {
        "is_codex_provider" => response_codex(request.provider_id.as_deref().unwrap_or_default()),
        "presentation_mode" => response_mode(
            request.provider_id.as_deref().unwrap_or_default(),
            request
                .separate_codex_thinking_messages_enabled
                .unwrap_or(false),
        ),
        "should_update_inline_reasoning_state" => response_selected_conversation(
            request.event_conversation_id.as_deref(),
            request.selected_conversation_id.as_deref(),
        ),
        "apply_stream_chunk" => apply_stream_chunk_response(request),
        _ => MainChatReasoningResponse::error(
            "unsupported_operation",
            "Unsupported reasoning operation",
        ),
    }
}

fn response_codex(provider_id: &str) -> MainChatReasoningResponse {
    MainChatReasoningResponse {
        schema_version: 1,
        error: None,
        presentation_mode: None,
        is_codex_provider: Some(is_codex_provider(provider_id)),
        should_update_inline_reasoning_state: None,
        state: None,
    }
}

fn response_mode(
    provider_id: &str,
    separate_codex_thinking_messages_enabled: bool,
) -> MainChatReasoningResponse {
    MainChatReasoningResponse {
        schema_version: 1,
        error: None,
        presentation_mode: Some(
            if separate_codex_thinking_messages_enabled && is_codex_provider(provider_id) {
                "separateMessages"
            } else {
                "inline"
            }
            .to_string(),
        ),
        is_codex_provider: None,
        should_update_inline_reasoning_state: None,
        state: None,
    }
}

fn response_selected_conversation(
    event_conversation_id: Option<&str>,
    selected_conversation_id: Option<&str>,
) -> MainChatReasoningResponse {
    MainChatReasoningResponse {
        schema_version: 1,
        error: None,
        presentation_mode: None,
        is_codex_provider: None,
        should_update_inline_reasoning_state: Some(matches!(
            (event_conversation_id, selected_conversation_id),
            (Some(event), Some(selected)) if !event.is_empty() && event == selected
        )),
        state: None,
    }
}

fn apply_stream_chunk_response(request: MainChatReasoningRequest) -> MainChatReasoningResponse {
    let Some(output) = request.output else {
        return MainChatReasoningResponse::error("missing_output", "output is required");
    };
    let Some(group_id) = request.group_id else {
        return MainChatReasoningResponse::error("missing_group_id", "groupId is required");
    };
    let Some(state) = request.state else {
        return MainChatReasoningResponse::error("missing_state", "state is required");
    };
    MainChatReasoningResponse {
        schema_version: 1,
        error: None,
        presentation_mode: None,
        is_codex_provider: None,
        should_update_inline_reasoning_state: None,
        state: Some(apply_stream_chunk(
            output,
            group_id,
            state,
            request
                .sequential_streaming_layout_enabled
                .unwrap_or(false),
            request.streaming_segment_turn_index.unwrap_or(0),
        )),
    }
}

fn apply_stream_chunk(
    output: String,
    group_id: String,
    state: MainChatReasoningState,
    sequential_streaming_layout_enabled: bool,
    streaming_segment_turn_index: i32,
) -> MainChatReasoningState {
    let mut next_state = state;
    if let Some(index) = next_state.blocks.iter().position(|item| item.id == group_id) {
        next_state.blocks[index].text =
            merge_reasoning_text(Some(next_state.blocks[index].text.clone()), output.clone());
    } else {
        next_state.blocks.push(MainChatReasoningBlock {
            id: group_id.clone(),
            text: output.clone(),
        });
    }
    next_state.text = Some(
        next_state
            .blocks
            .iter()
            .map(|item| item.text.clone())
            .collect::<Vec<_>>()
            .join("\n\n"),
    );
    if !sequential_streaming_layout_enabled {
        return next_state;
    }

    let segment_id = format!("reasoning-{streaming_segment_turn_index}");
    let current_block_text = next_state
        .blocks
        .iter()
        .rev()
        .find(|item| item.id == group_id)
        .map(|item| item.text.clone())
        .unwrap_or(output);
    if let Some(index) = next_state.segments.iter().position(|segment| segment.id == segment_id) {
        next_state.segments[index].kind = "reasoning".to_string();
        next_state.segments[index].text = current_block_text;
    } else {
        next_state.segments.push(MainChatReasoningSegment {
            id: segment_id,
            kind: "reasoning".to_string(),
            text: current_block_text,
        });
    }
    next_state
}

fn is_codex_provider(provider_id: &str) -> bool {
    let normalized = provider_id.trim().to_lowercase();
    !normalized.is_empty() && normalized.contains("codex")
}

fn merge_reasoning_text(existing: Option<String>, incoming: String) -> String {
    let existing = existing.unwrap_or_default();
    if existing.is_empty() || incoming.starts_with(&existing) {
        return incoming;
    }
    let overlap = reasoning_suffix_prefix_overlap_length(&existing, &incoming);
    if overlap == 0 {
        return incoming;
    }
    let suffix = incoming.chars().skip(overlap).collect::<String>();
    format!("{existing}{suffix}")
}

fn reasoning_suffix_prefix_overlap_length(lhs: &str, rhs: &str) -> usize {
    let max_overlap = lhs.len().min(rhs.len());
    for length in (1..=max_overlap).rev() {
        if lhs[lhs.len() - length..] == rhs[..length] {
            return length;
        }
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codex_defaults_to_inline_mode() {
        let response = response_mode("codex-cli", false);
        assert_eq!(response.presentation_mode.as_deref(), Some("inline"));
    }

    #[test]
    fn reducer_merges_chunks_into_single_reasoning_block() {
        let first = apply_stream_chunk(
            "Planning next move".to_string(),
            "reasoning-stream".to_string(),
            MainChatReasoningState::default(),
            false,
            0,
        );
        let second = apply_stream_chunk(
            "Planning next move\nReading files".to_string(),
            "reasoning-stream".to_string(),
            first,
            false,
            0,
        );
        assert_eq!(second.blocks.len(), 1);
        assert_eq!(second.blocks[0].id, "reasoning-stream");
        assert_eq!(second.blocks[0].text, "Planning next move\nReading files");
        assert_eq!(second.text.as_deref(), Some("Planning next move\nReading files"));
    }

    #[test]
    fn inline_reasoning_updates_only_for_selected_conversation() {
        assert_eq!(
            response_selected_conversation(Some("a"), Some("a"))
                .should_update_inline_reasoning_state,
            Some(true)
        );
        assert_eq!(
            response_selected_conversation(Some("a"), Some("b"))
                .should_update_inline_reasoning_state,
            Some(false)
        );
        assert_eq!(
            response_selected_conversation(None, Some("b"))
                .should_update_inline_reasoning_state,
            Some(false)
        );
    }
}
