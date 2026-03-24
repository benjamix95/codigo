use app_core_protocol::main_chat::{MainChatArtifact, MainChatArtifactKind, MainChatTurnState};
use app_core_protocol::main_chat_runtime::{
    MainChatPlanPhase, MainChatPlanSnapshot, MainChatRuntimeOutput,
};
use app_core_protocol::main_chat_store::{
    MainChatStoreConversationSnapshot, MainChatStoreMessageSnapshot, MainChatStorePlanBoardSnapshot,
};
use app_core_protocol::main_chat_task_runtime::MainChatTaskStateSnapshot;
use app_core_protocol::main_chat_ui::{
    timeline_block_from_store, MainChatUiComposerSnapshot, MainChatUiConversationSummary,
    MainChatUiMessageSnapshot, MainChatUiPlanSnapshot, MainChatUiProjectRequest,
    MainChatUiProjectResponse, MainChatUiSnapshot, MainChatUiTaskSnapshot,
    MainChatUiTimelineBlockSnapshot,
};

pub fn project_ui(request: MainChatUiProjectRequest) -> MainChatUiProjectResponse {
    if request.schema_version != 1 {
        return MainChatUiProjectResponse::error("unsupported_schema", "schemaVersion must be 1");
    }

    let state = request.state;
    let selected_conversation_id = resolve_selected_conversation_id(&state);
    let conversations = state
        .store_snapshot
        .conversations
        .iter()
        .map(|conversation| {
            conversation_summary(conversation, selected_conversation_id.as_deref(), &state)
        })
        .collect::<Vec<_>>();
    let selected_conversation = selected_conversation_id
        .as_deref()
        .and_then(|conversation_id| {
            state
                .store_snapshot
                .conversations
                .iter()
                .find(|conversation| conversation.id == conversation_id)
        });
    let messages = selected_conversation
        .map(|conversation| selected_messages(conversation, &state))
        .unwrap_or_default();
    let task = task_snapshot(selected_conversation_id.as_deref(), &state);
    let plan = plan_snapshot(selected_conversation_id.as_deref(), &state);
    let composer = MainChatUiComposerSnapshot {
        draft_text: state.draft_text.clone(),
        can_send: !state.draft_text.trim().is_empty() && !task.is_loading,
        can_cancel: task.is_loading,
        is_following_live: state.follow_live,
    };
    MainChatUiProjectResponse::success(MainChatUiSnapshot {
        selected_conversation_id,
        conversations,
        messages,
        composer,
        task,
        plan,
        follow_up_prompt: state
            .runtime_snapshot
            .as_ref()
            .and_then(|snapshot| snapshot.output.as_ref())
            .and_then(|output| output.follow_up_prompt.clone()),
        generated_prompt: state
            .runtime_snapshot
            .as_ref()
            .and_then(|snapshot| snapshot.output.as_ref())
            .and_then(|output| output.generated_prompt.clone()),
        is_empty: state.store_snapshot.conversations.is_empty(),
    })
}

fn resolve_selected_conversation_id(
    state: &app_core_protocol::main_chat_ui::MainChatUiState,
) -> Option<String> {
    if let Some(selected) = state.selected_conversation_id.as_ref() {
        if state
            .store_snapshot
            .conversations
            .iter()
            .any(|conversation| &conversation.id == selected)
        {
            return Some(selected.clone());
        }
    }
    state
        .store_snapshot
        .conversations
        .iter()
        .find(|conversation| !conversation.is_archived)
        .or_else(|| state.store_snapshot.conversations.first())
        .map(|conversation| conversation.id.clone())
}

fn conversation_summary(
    conversation: &MainChatStoreConversationSnapshot,
    selected_conversation_id: Option<&str>,
    state: &app_core_protocol::main_chat_ui::MainChatUiState,
) -> MainChatUiConversationSummary {
    MainChatUiConversationSummary {
        id: conversation.id.clone(),
        title: conversation.title.clone(),
        message_count: conversation.messages.len() as i32,
        last_message_preview: conversation.messages.last().and_then(message_preview),
        mode: conversation.mode.clone(),
        preferred_provider_id: conversation.preferred_provider_id.clone(),
        is_archived: conversation.is_archived,
        is_selected: selected_conversation_id == Some(conversation.id.as_str()),
        is_loading: task_state_for(&conversation.id, state).is_some(),
    }
}

fn selected_messages(
    conversation: &MainChatStoreConversationSnapshot,
    state: &app_core_protocol::main_chat_ui::MainChatUiState,
) -> Vec<MainChatUiMessageSnapshot> {
    conversation
        .messages
        .iter()
        .map(|message| message_snapshot(message, state))
        .collect()
}

fn message_snapshot(
    message: &MainChatStoreMessageSnapshot,
    state: &app_core_protocol::main_chat_ui::MainChatUiState,
) -> MainChatUiMessageSnapshot {
    let runtime_turn = active_turn_for_message(message, state);
    let turn_id = message
        .turn_metadata
        .as_ref()
        .map(|metadata| metadata.turn_id.clone())
        .or_else(|| runtime_turn.map(|turn_state| turn_state.turn_id.clone()));
    let collapsed_ids = turn_id
        .as_ref()
        .and_then(|value| state.collapsed_artifact_ids_by_turn.get(value))
        .cloned()
        .unwrap_or_default();
    let mut timeline_blocks = message
        .blocks
        .clone()
        .unwrap_or_default()
        .iter()
        .map(|block| timeline_block_from_store(block, collapsed_ids.contains(&block.id)))
        .collect::<Vec<_>>();
    if let Some(turn_state) = runtime_turn {
        timeline_blocks.extend(
            turn_state
                .artifacts
                .iter()
                .map(|artifact| artifact_block(artifact, &collapsed_ids)),
        );
    }

    let primary_text = runtime_turn
        .map(turn_primary_text)
        .filter(|text| !text.is_empty())
        .or_else(|| message.primary_text_snapshot.clone())
        .or_else(|| (!message.content.is_empty()).then(|| message.content.clone()));
    let reasoning_text = runtime_turn
        .map(turn_reasoning_text)
        .filter(|text| !text.is_empty())
        .or_else(|| message.reasoning_text.clone());
    MainChatUiMessageSnapshot {
        id: message.id.clone(),
        role: message.role.clone(),
        turn_id,
        content: runtime_turn
            .and_then(|_| state.runtime_snapshot.as_ref())
            .and_then(|snapshot| snapshot.output.as_ref())
            .and_then(|output| output.chat_content_override.clone())
            .unwrap_or_else(|| message.content.clone()),
        primary_text,
        reasoning_text,
        turn_status: runtime_turn
            .map(|turn_state| turn_state.status.clone())
            .or_else(|| {
                message
                    .turn_metadata
                    .as_ref()
                    .map(|metadata| metadata.status.clone())
            }),
        is_streaming: runtime_turn
            .map(|turn_state| turn_state.is_streaming)
            .unwrap_or(message.is_streaming),
        timeline_blocks,
        subagent_cards: message.subagent_cards.clone().unwrap_or_default(),
    }
}

fn task_snapshot(
    selected_conversation_id: Option<&str>,
    state: &app_core_protocol::main_chat_ui::MainChatUiState,
) -> MainChatUiTaskSnapshot {
    let task_state =
        selected_conversation_id.and_then(|conversation_id| task_state_for(conversation_id, state));
    let runtime_output = state
        .runtime_snapshot
        .as_ref()
        .and_then(|snapshot| snapshot.output.as_ref());
    MainChatUiTaskSnapshot {
        is_loading: task_state.is_some()
            || state
                .runtime_snapshot
                .as_ref()
                .map(|snapshot| snapshot.turn_state.is_streaming)
                .unwrap_or(false),
        started_at: task_state.and_then(|task| task.started_at).or_else(|| {
            state
                .runtime_snapshot
                .as_ref()
                .and_then(|snapshot| snapshot.turn_state.started_at)
        }),
        status_text: task_state.map(|task| task.status_text.clone()).or_else(|| {
            state
                .runtime_snapshot
                .as_ref()
                .map(|snapshot| snapshot.turn_state.status.clone())
        }),
        terminal_error: runtime_output.and_then(|output| output.terminal_error.clone()),
        should_retry_poll: runtime_output
            .map(|output| output.should_retry_poll)
            .unwrap_or(false),
        should_finalize_stream: runtime_output
            .map(|output| output.should_finalize_stream)
            .unwrap_or(false),
    }
}

fn plan_snapshot(
    selected_conversation_id: Option<&str>,
    state: &app_core_protocol::main_chat_ui::MainChatUiState,
) -> MainChatUiPlanSnapshot {
    let runtime_plan = state
        .runtime_snapshot
        .as_ref()
        .and_then(|snapshot| snapshot.plan.as_ref());
    let runtime_output = state
        .runtime_snapshot
        .as_ref()
        .and_then(|snapshot| snapshot.output.as_ref());
    let plan_board = selected_conversation_id
        .and_then(|conversation_id| state.store_snapshot.plan_boards.get(conversation_id));
    plan_snapshot_from_sources(
        runtime_plan,
        runtime_output,
        plan_board,
        state.plan_panel_visible,
    )
}

fn plan_snapshot_from_sources(
    runtime_plan: Option<&MainChatPlanSnapshot>,
    runtime_output: Option<&MainChatRuntimeOutput>,
    plan_board: Option<&MainChatStorePlanBoardSnapshot>,
    plan_panel_visible: bool,
) -> MainChatUiPlanSnapshot {
    MainChatUiPlanSnapshot {
        is_visible: plan_panel_visible
            || runtime_output
                .map(|output| output.should_open_plan_panel)
                .unwrap_or(false)
            || runtime_plan.is_some()
            || plan_board.is_some(),
        phase: runtime_plan.and_then(|plan| plan.phase.clone()),
        planning_state_kind: runtime_plan.and_then(|plan| plan.planning_state_kind.clone()),
        question_epoch: runtime_plan
            .map(|plan| plan.question_epoch)
            .unwrap_or_default(),
        clarification_questions: runtime_plan.and_then(|plan| plan.clarification_questions.clone()),
        clarification_questionnaire: runtime_plan
            .and_then(|plan| plan.clarification_questionnaire.clone()),
        proposal_content: runtime_plan
            .and_then(|plan| plan.proposal_content.clone())
            .or_else(|| plan_board.and_then(|board| board.walkthrough_markdown.clone())),
        summary_title: runtime_plan.and_then(|plan| plan.summary_title.clone()),
        chosen_path: runtime_plan
            .and_then(|plan| plan.chosen_path.clone())
            .or_else(|| plan_board.and_then(|board| board.chosen_path.clone())),
        option_full_texts: runtime_plan
            .map(|plan| plan.option_full_texts.clone())
            .unwrap_or_default(),
        option_titles: runtime_plan
            .map(|plan| plan.option_titles.clone())
            .unwrap_or_default(),
        canonical_todos: runtime_plan
            .map(|plan| plan.canonical_todos.clone())
            .unwrap_or_default(),
        goal: runtime_plan
            .and_then(|plan| plan.summary_title.clone())
            .or_else(|| plan_board.map(|board| board.goal.clone()))
            .unwrap_or_default(),
        step_count: runtime_plan
            .map(|plan| plan.canonical_todos.len() as i32)
            .filter(|count| *count > 0)
            .or_else(|| plan_board.map(|board| board.steps.len() as i32))
            .unwrap_or_default(),
        should_hide_markdown: runtime_output
            .map(|output| output.should_hide_plan_markdown)
            .unwrap_or(false),
        should_run_inline: runtime_plan
            .map(|plan| plan.should_run_inline)
            .unwrap_or(false),
        is_ready_to_build: runtime_plan
            .and_then(|plan| plan.phase.as_ref())
            .map(|phase| phase == &MainChatPlanPhase::ReadyToBuild)
            .unwrap_or(false),
    }
}

fn task_state_for<'a>(
    conversation_id: &str,
    state: &'a app_core_protocol::main_chat_ui::MainChatUiState,
) -> Option<&'a MainChatTaskStateSnapshot> {
    state
        .task_runtime_state
        .as_ref()?
        .task_states
        .iter()
        .find(|task| task.conversation_id == conversation_id)
}

fn active_turn_for_message<'a>(
    message: &MainChatStoreMessageSnapshot,
    state: &'a app_core_protocol::main_chat_ui::MainChatUiState,
) -> Option<&'a MainChatTurnState> {
    state
        .runtime_snapshot
        .as_ref()
        .filter(|snapshot| snapshot.turn_state.assistant_message_id == message.id)
        .map(|snapshot| &snapshot.turn_state)
}

fn message_preview(message: &MainChatStoreMessageSnapshot) -> Option<String> {
    let candidate = message
        .primary_text_snapshot
        .as_ref()
        .unwrap_or(&message.content)
        .trim();
    (!candidate.is_empty()).then(|| candidate.chars().take(80).collect())
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

fn turn_reasoning_text(turn_state: &MainChatTurnState) -> String {
    turn_state
        .reasoning_by_group_id
        .values()
        .cloned()
        .collect::<Vec<_>>()
        .join("\n\n")
}

fn artifact_block(
    artifact: &MainChatArtifact,
    collapsed_ids: &[String],
) -> MainChatUiTimelineBlockSnapshot {
    MainChatUiTimelineBlockSnapshot {
        id: artifact.id.clone(),
        kind: artifact_kind_label(&artifact.kind).to_string(),
        title: Some(artifact.title.clone()),
        text: artifact.text.clone(),
        items: artifact.items.clone(),
        metadata: artifact.metadata.clone(),
        is_collapsible: artifact.is_collapsible,
        is_collapsed_by_default: artifact.is_collapsed_by_default,
        is_collapsed: collapsed_ids.contains(&artifact.id),
    }
}

fn artifact_kind_label(kind: &MainChatArtifactKind) -> &'static str {
    match kind {
        MainChatArtifactKind::Mermaid => "mermaid",
        MainChatArtifactKind::Commands => "commands",
        MainChatArtifactKind::Files => "files",
        MainChatArtifactKind::Status => "status",
        MainChatArtifactKind::Plan => "plan",
        MainChatArtifactKind::ToolTrace => "toolTrace",
    }
}
