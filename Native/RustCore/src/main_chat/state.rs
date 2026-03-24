use app_core_protocol::main_chat_runtime::{
    MainChatDirectStreamSnapshot, MainChatPlanPhase, MainChatPlanSnapshot,
    MainChatPlanningStateKind, MainChatRuntimeMode, MainChatRuntimeOutput, MainChatRuntimeSnapshot,
};

pub fn ensure_direct_stream_defaults(snapshot: &mut MainChatRuntimeSnapshot) {
    snapshot
        .mode
        .get_or_insert(MainChatRuntimeMode::DirectStream);
    snapshot
        .direct_stream
        .get_or_insert_with(|| MainChatDirectStreamSnapshot {
            first_event_timeout_sec: 90,
            activity_timeout_sec: 1800,
            max_initial_retries: 4,
            max_stall_retries: 12,
            ..Default::default()
        });
    snapshot
        .output
        .get_or_insert_with(MainChatRuntimeOutput::default);
}

pub fn ensure_plan_defaults(snapshot: &mut MainChatRuntimeSnapshot) {
    snapshot.mode.get_or_insert(MainChatRuntimeMode::Plan);
    snapshot.plan.get_or_insert_with(|| MainChatPlanSnapshot {
        phase: Some(MainChatPlanPhase::Idle),
        planning_state_kind: Some(MainChatPlanningStateKind::Idle),
        ..Default::default()
    });
    snapshot
        .output
        .get_or_insert_with(MainChatRuntimeOutput::default);
}

pub fn reset_output(snapshot: &mut MainChatRuntimeSnapshot) {
    snapshot.output = Some(MainChatRuntimeOutput::default());
}
