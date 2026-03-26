use super::plan_runtime::handle_plan_action;
use app_core_protocol::main_chat::MainChatTurnState;
use app_core_protocol::main_chat_runtime::{
    MainChatPlanPhase, MainChatPlanningStateKind, MainChatRuntimeSnapshot,
};

#[test]
fn screening_no_plan_skips_panel_and_flags_pipeline_skip() {
    let snapshot = handle_plan_action(
        base_snapshot(),
        "plan_apply_screening_result",
        Some("Quick fix.\nNO_PLAN_NEEDED".to_string()),
        None,
        None,
        Vec::new(),
        None,
    )
    .expect("snapshot");
    let plan = snapshot.plan.expect("plan");
    assert_eq!(plan.phase, Some(MainChatPlanPhase::Idle));
    assert_eq!(
        plan.planning_state_kind,
        Some(MainChatPlanningStateKind::Idle)
    );
    let output = snapshot.output.expect("output");
    assert!(!output.should_open_plan_panel);
    assert!(output.skip_full_plan_pipeline);
}

#[test]
fn phase2_action_opens_panel_and_sets_questions() {
    let snapshot = handle_plan_action(
        base_snapshot(),
        "plan_apply_question_result",
        Some("## Questions\n1. Which module?".to_string()),
        None,
        None,
        Vec::new(),
        None,
    )
    .expect("snapshot");
    let plan = snapshot.plan.expect("plan");
    assert_eq!(plan.phase, Some(MainChatPlanPhase::Questioning));
    assert_eq!(
        plan.planning_state_kind,
        Some(MainChatPlanningStateKind::AwaitingClarification)
    );
    assert!(snapshot
        .output
        .as_ref()
        .is_some_and(|it| it.should_open_plan_panel));
}

#[test]
fn generation_promotes_proposal_ready_when_todo_plan_exists() {
    let snapshot = handle_plan_action(
        base_snapshot(),
        "plan_apply_generation_result",
        Some("## Plan: Title\n## Todo\n- [ ] Step".to_string()),
        None,
        None,
        Vec::new(),
        None,
    )
    .expect("snapshot");
    let plan = snapshot.plan.expect("plan");
    assert_eq!(plan.phase, Some(MainChatPlanPhase::ProposalReady));
    assert_eq!(plan.option_full_texts.len(), 1);
}

fn base_snapshot() -> MainChatRuntimeSnapshot {
    MainChatRuntimeSnapshot {
        turn_state: MainChatTurnState {
            conversation_id: "conv".to_string(),
            assistant_message_id: "msg".to_string(),
            turn_id: "turn".to_string(),
            status: "idle".to_string(),
            ..Default::default()
        },
        ..Default::default()
    }
}
