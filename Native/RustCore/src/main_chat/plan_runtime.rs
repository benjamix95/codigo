use crate::main_chat::plan_prompts::{
    build_phase0_screening_prompt, build_phase1_analysis_prompt, build_phase2_question_prompt,
    build_phase3_generation_prompt, build_phase3_repair_prompt,
    build_post_clarification_analysis_prompt,
};
use crate::main_chat::state::{ensure_plan_defaults, reset_output};
use app_core_protocol::main_chat_runtime::{
    MainChatPlanPhase, MainChatPlanningStateKind, MainChatRuntimeSnapshot,
};

pub fn handle_plan_action(
    mut snapshot: MainChatRuntimeSnapshot,
    action: &str,
    text: Option<String>,
    questions: Option<String>,
    plan_content: Option<String>,
    option_full_texts: Vec<String>,
    should_run_inline: Option<bool>,
) -> Option<MainChatRuntimeSnapshot> {
    if !action.starts_with("plan_") {
        return None;
    }
    ensure_plan_defaults(&mut snapshot);
    reset_output(&mut snapshot);
    let plan = snapshot.plan.as_mut().expect("plan");

    match action {
        "plan_prepare_phase0_screening_prompt" => {
            plan.user_request = text.unwrap_or_default();
            plan.should_run_inline = should_run_inline.unwrap_or(plan.should_run_inline);
            snapshot.output.as_mut()?.generated_prompt =
                Some(build_phase0_screening_prompt(&plan.user_request));
        }
        "plan_apply_screening_result" => {
            plan.phase = Some(MainChatPlanPhase::Analyzing);
            snapshot.output.as_mut()?.chat_content_override =
                Some(plan_screening_status_message(parse_plan_screening_decision(
                    text.as_deref().unwrap_or_default(),
                )));
            snapshot.output.as_mut()?.should_open_plan_panel = true;
        }
        "plan_prepare_phase1_analysis_prompt" => {
            plan.phase = Some(MainChatPlanPhase::Analyzing);
            plan.planning_state_kind = Some(MainChatPlanningStateKind::Idle);
            if let Some(user_request) = text {
                plan.user_request = user_request;
            }
            plan.should_run_inline = should_run_inline.unwrap_or(plan.should_run_inline);
            snapshot.output.as_mut()?.generated_prompt =
                Some(build_phase1_analysis_prompt(&plan.user_request));
            snapshot.output.as_mut()?.should_open_plan_panel = true;
        }
        "plan_store_analysis_context" => {
            plan.analysis_context = text.unwrap_or_default();
        }
        "plan_apply_analysis_result" => {
            plan.analysis_context = text.unwrap_or_default();
            if should_ask_plan_clarifications(&plan.analysis_context, &plan.user_request) {
                plan.phase = Some(MainChatPlanPhase::Questioning);
                plan.planning_state_kind = Some(MainChatPlanningStateKind::Idle);
                snapshot.output.as_mut()?.generated_prompt =
                    Some(build_phase2_question_prompt(&plan.user_request, &plan.analysis_context));
            } else {
                plan.phase = Some(MainChatPlanPhase::Generating);
                plan.planning_state_kind = Some(MainChatPlanningStateKind::Idle);
                snapshot.output.as_mut()?.generated_prompt = Some(build_phase3_generation_prompt(
                    &plan.user_request,
                    &plan.analysis_context,
                    &plan.clarification_answers,
                ));
            }
        }
        "plan_prepare_phase2_questions_prompt" => {
            plan.phase = Some(MainChatPlanPhase::Questioning);
            snapshot.output.as_mut()?.generated_prompt =
                Some(build_phase2_question_prompt(&plan.user_request, &plan.analysis_context));
        }
        "plan_apply_question_result" => {
            let question_text = text.unwrap_or_default();
            if let Some(questions_markdown) = extract_clarification_payload(&question_text) {
                plan.phase = Some(MainChatPlanPhase::Questioning);
                plan.planning_state_kind = Some(MainChatPlanningStateKind::AwaitingClarification);
                plan.clarification_cycles += 1;
                plan.clarification_questions = Some(questions_markdown);
                snapshot.output.as_mut()?.chat_content_override =
                    Some("Questions ready — answer in the plan panel.".to_string());
                snapshot.output.as_mut()?.should_open_plan_panel = true;
            } else {
                plan.phase = Some(MainChatPlanPhase::Generating);
                plan.planning_state_kind = Some(MainChatPlanningStateKind::Idle);
                snapshot.output.as_mut()?.generated_prompt = Some(build_phase3_generation_prompt(
                    &plan.user_request,
                    &plan.analysis_context,
                    &plan.clarification_answers,
                ));
                snapshot.output.as_mut()?.chat_content_override = Some(
                    if has_no_questions_needed_signal(&question_text) {
                        "No questions needed. Generating plan..."
                    } else {
                        "Question phase completed. Generating plan..."
                    }
                    .to_string(),
                );
            }
        }
        "plan_apply_clarification_answers" => {
            plan.clarification_answers = text.unwrap_or_default();
            plan.planning_state_kind = Some(MainChatPlanningStateKind::Idle);
            plan.phase = Some(MainChatPlanPhase::Analyzing);
        }
        "plan_prepare_post_clarification_analysis_prompt" => {
            plan.phase = Some(MainChatPlanPhase::Analyzing);
            snapshot.output.as_mut()?.generated_prompt =
                Some(build_post_clarification_analysis_prompt(
                    &plan.user_request,
                    &plan.analysis_context,
                    &plan.clarification_answers,
                ));
        }
        "plan_apply_post_clarification_analysis_result" => {
            let post_analysis = text.unwrap_or_default();
            plan.analysis_context = format!(
                "{}\n\n--- Post-clarification analysis ---\n{}",
                plan.analysis_context, post_analysis
            )
            .trim()
            .to_string();
            if should_allow_follow_up_clarification(&plan.user_request, plan.clarification_cycles) {
                if let Some(questions_markdown) = extract_clarification_payload(&post_analysis) {
                    plan.phase = Some(MainChatPlanPhase::Questioning);
                    plan.planning_state_kind = Some(MainChatPlanningStateKind::AwaitingClarification);
                    plan.clarification_cycles += 1;
                    plan.clarification_questions = Some(questions_markdown);
                    snapshot.output.as_mut()?.chat_content_override =
                        Some("Questions ready — answer in the plan panel.".to_string());
                    snapshot.output.as_mut()?.should_open_plan_panel = true;
                    return Some(snapshot);
                }
            }
            plan.phase = Some(MainChatPlanPhase::Generating);
            plan.planning_state_kind = Some(MainChatPlanningStateKind::Idle);
            snapshot.output.as_mut()?.generated_prompt = Some(build_phase3_generation_prompt(
                &plan.user_request,
                &plan.analysis_context,
                &plan.clarification_answers,
            ));
            snapshot.output.as_mut()?.chat_content_override =
                Some("Questions answered. Generating definitive plan...".to_string());
        }
        "plan_prepare_phase3_generation_prompt" => {
            plan.phase = Some(MainChatPlanPhase::Generating);
            plan.planning_state_kind = Some(MainChatPlanningStateKind::Idle);
            snapshot.output.as_mut()?.generated_prompt = Some(build_phase3_generation_prompt(
                &plan.user_request,
                &plan.analysis_context,
                &plan.clarification_answers,
            ));
        }
        "plan_prepare_phase3_repair_prompt" => {
            snapshot.output.as_mut()?.generated_prompt = Some(build_phase3_repair_prompt(
                &plan.user_request,
                &plan.analysis_context,
                &plan.clarification_answers,
                text.as_deref().unwrap_or_default(),
            ));
        }
        "plan_apply_generation_result" => {
            let generation = text.unwrap_or_default();
            if let Some(questions_markdown) = clarifications_needed_section(&generation) {
                plan.phase = Some(MainChatPlanPhase::Questioning);
                plan.planning_state_kind = Some(MainChatPlanningStateKind::AwaitingClarification);
                plan.clarification_cycles += 1;
                plan.clarification_questions = Some(questions_markdown);
                snapshot.output.as_mut()?.chat_content_override =
                    Some("Additional clarifications needed — answer in the plan panel.".to_string());
                snapshot.output.as_mut()?.should_open_plan_panel = true;
            } else if has_todo_compliant_plan(&generation) {
                plan.phase = Some(MainChatPlanPhase::ProposalReady);
                plan.planning_state_kind = Some(MainChatPlanningStateKind::AwaitingChoice);
                plan.proposal_content = Some(generation.clone());
                plan.option_full_texts = vec![generation];
                snapshot.output.as_mut()?.should_open_plan_panel = true;
                snapshot.output.as_mut()?.should_hide_plan_markdown = true;
            } else {
                snapshot.output.as_mut()?.generated_prompt = Some(build_phase3_repair_prompt(
                    &plan.user_request,
                    &plan.analysis_context,
                    &plan.clarification_answers,
                    &generation,
                ));
            }
        }
        "plan_store_proposal" => {
            plan.phase = Some(MainChatPlanPhase::ProposalReady);
            plan.planning_state_kind = Some(MainChatPlanningStateKind::AwaitingChoice);
            plan.proposal_content = plan_content.or(text);
            plan.option_full_texts = option_full_texts;
            snapshot.output.as_mut()?.should_open_plan_panel = true;
        }
        "plan_ready_to_build" => {
            plan.phase = Some(MainChatPlanPhase::ReadyToBuild);
            plan.planning_state_kind = Some(MainChatPlanningStateKind::Idle);
        }
        "plan_begin_build" => {
            plan.phase = Some(MainChatPlanPhase::Building);
            plan.planning_state_kind = Some(MainChatPlanningStateKind::Idle);
        }
        "plan_reset" => {
            *plan = Default::default();
            plan.phase = Some(MainChatPlanPhase::Idle);
            plan.planning_state_kind = Some(MainChatPlanningStateKind::Idle);
        }
        _ => {}
    }
    Some(snapshot)
}

fn parse_plan_screening_decision(text: &str) -> &'static str {
    let normalized = text.trim().to_uppercase();
    if normalized.ends_with("NO_PLAN_NEEDED") {
        "no_plan_needed"
    } else if normalized.ends_with("PLAN_NEEDED") {
        "plan_needed"
    } else {
        "unknown"
    }
}

fn plan_screening_status_message(decision: &str) -> String {
    match decision {
        "no_plan_needed" => "Request looks straightforward. Continuing...".to_string(),
        _ => "Starting codebase analysis...".to_string(),
    }
}

fn should_ask_plan_clarifications(analysis_text: &str, user_request: &str) -> bool {
    let normalized = format!("{analysis_text}\n{user_request}").to_lowercase();
    ["blocked", "cannot proceed", "ambiguous", "unclear", "missing requirement", "need clarification"]
        .iter()
        .any(|pattern| normalized.contains(pattern))
}

fn should_allow_follow_up_clarification(user_request: &str, clarification_cycles: i32) -> bool {
    clarification_cycles < 2
        && ["ask", "chiedi", "clarification"].iter().any(|pattern| user_request.to_lowercase().contains(pattern))
}

fn extract_clarification_payload(text: &str) -> Option<String> {
    let lower = text.to_lowercase();
    if lower.contains("## questions")
        || lower.contains("clarification questions")
        || lower.contains("clarifications needed")
    {
        Some(text.trim().to_string())
    } else {
        None
    }
}

fn has_no_questions_needed_signal(text: &str) -> bool {
    let lower = text.to_lowercase();
    lower.contains("no_questions_needed") || lower.contains("no questions needed")
}

fn clarifications_needed_section(text: &str) -> Option<String> {
    let lower = text.to_lowercase();
    lower
        .find("clarifications needed")
        .map(|index| text[index..].trim().to_string())
}

fn has_todo_compliant_plan(text: &str) -> bool {
    let lower = text.to_lowercase();
    lower.contains("## plan") && lower.contains("## todo")
}
