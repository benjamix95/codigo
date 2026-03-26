use super::finalize::patchable_verified_finding_ids;
use super::models::{ReviewPipelineResponse, ReviewPipelineStep};
use super::requests::{
    ReviewPipelineApplyRequest, ReviewPipelineCallbackResult, ReviewPipelineSessionRequest,
    ReviewPipelineStartRequest,
};
use super::scope::{
    infer_review_scope, parse_against_ref, parse_review_scope, review_scope_description,
};
use super::state::{
    analysis_completed, append_events, complete, fail, has_blocking_open_findings,
    mark_open_findings_fix_applied, replace_findings, replace_open_findings_in_files,
    replace_patches, set_scope, upsert_candidates, upsert_findings, PipelineSession,
};
use super::tasks::{
    classify_review_outcome, parse_review_tasks, ReviewFindingsState, TaskExtraction,
};
use std::collections::HashMap;
use std::sync::{OnceLock, RwLock};

static SESSIONS: OnceLock<RwLock<HashMap<String, PipelineSession>>> = OnceLock::new();

pub fn start_session(request: ReviewPipelineStartRequest) -> ReviewPipelineResponse {
    let (prompt_without_scope, explicit_scope) = parse_review_scope(&request.prompt);
    let (clean_prompt, against_ref) = parse_against_ref(&prompt_without_scope);
    let resolved_scope = explicit_scope.unwrap_or_else(|| infer_review_scope(&clean_prompt));
    let session = PipelineSession::new(
        request.session_id.clone(),
        request.conversation_id.clone(),
        request.workspace_path,
        request.config,
        clean_prompt,
        against_ref,
        resolved_scope,
    );
    let response = ReviewPipelineResponse::success(
        request.session_id.clone(),
        session.snapshot.clone(),
        session.step.clone(),
    );
    sessions()
        .write()
        .unwrap_or_else(|err| err.into_inner())
        .insert(request.session_id, session);
    response
}

pub fn apply_callback_result(request: ReviewPipelineApplyRequest) -> ReviewPipelineResponse {
    let mut sessions = sessions()
        .write()
        .unwrap_or_else(|err| err.into_inner());
    let Some(session) = sessions.get_mut(&request.session_id) else {
        return missing_session(&request.session_id);
    };
    let next_step = match session.step.kind.as_str() {
        "resolve_scope_files" => on_resolve_scope_files(session, request.callback),
        "run_audit_stage" => on_run_audit_stage(session, request.callback),
        "request_analysis_stream" => on_analysis(session, request.callback),
        "prepare_task_candidates" => on_prepare_task_candidates(session, request.callback),
        "run_fix_stage" => on_fix_stage(session, request.callback),
        "run_tests" => on_run_tests(session, request.callback),
        "scan_modified_files" => on_scan_modified_files(session, request.callback),
        "request_rereview_stream" => on_rereview(session, request.callback),
        "prepare_verified_patches" => on_prepare_verified_patches(session, request.callback),
        "completed" | "failed" => session.step.clone(),
        _ => ReviewPipelineStep::failed("unsupported_step"),
    };
    session.step = next_step.clone();
    ReviewPipelineResponse::success(request.session_id, session.snapshot.clone(), next_step)
}

pub fn get_snapshot(request: ReviewPipelineSessionRequest) -> ReviewPipelineResponse {
    let sessions = sessions()
        .read()
        .unwrap_or_else(|err| err.into_inner());
    if let Some(session) = sessions.get(&request.session_id) {
        return ReviewPipelineResponse::success(
            request.session_id,
            session.snapshot.clone(),
            session.step.clone(),
        );
    }
    missing_session(&request.session_id)
}

pub fn resume_session(request: ReviewPipelineSessionRequest) -> ReviewPipelineResponse {
    get_snapshot(request)
}

pub fn cancel_session(request: ReviewPipelineSessionRequest) -> ReviewPipelineResponse {
    let mut sessions = sessions()
        .write()
        .unwrap_or_else(|err| err.into_inner());
    if let Some(session) = sessions.get_mut(&request.session_id) {
        fail(session, "Review cancelled.".to_string());
        session.step = ReviewPipelineStep::failed("Review cancelled.");
        return ReviewPipelineResponse::success(
            request.session_id,
            session.snapshot.clone(),
            session.step.clone(),
        );
    }
    missing_session(&request.session_id)
}

fn on_resolve_scope_files(
    session: &mut PipelineSession,
    callback: ReviewPipelineCallbackResult,
) -> ReviewPipelineStep {
    set_scope(session, callback.files.clone());
    if callback.files.is_empty() {
        complete(session, None);
        return ReviewPipelineStep::completed(None);
    }
    ReviewPipelineStep::run_audit(callback.files)
}

fn on_run_audit_stage(
    session: &mut PipelineSession,
    callback: ReviewPipelineCallbackResult,
) -> ReviewPipelineStep {
    append_events(session, &callback.events);
    if let Some(audit) = callback.audit {
        session.snapshot.audit = audit;
    }
    upsert_findings(session, &callback.findings);
    upsert_candidates(session, &callback.candidates);
    upsert_findings(session, &callback.promoted_findings);
    ReviewPipelineStep::analysis(
        session.clean_prompt.clone(),
        review_scope_description(&session.resolved_scope, session.against_ref.as_deref()),
        session
            .snapshot
            .scope
            .as_ref()
            .map(|scope| scope.files.clone())
            .unwrap_or_default(),
        session.snapshot.config.max_workers,
    )
}

fn on_analysis(
    session: &mut PipelineSession,
    callback: ReviewPipelineCallbackResult,
) -> ReviewPipelineStep {
    if let Some(message) = callback.error {
        fail(session, format!("Analysis stream failed: {message}"));
        return ReviewPipelineStep::failed(format!("Analysis stream failed: {message}"));
    }
    analysis_completed(session);
    let text = callback.text.unwrap_or_default();
    match parse_review_tasks(
        &text,
        &session
            .snapshot
            .scope
            .as_ref()
            .map(|scope| scope.files.clone())
            .unwrap_or_default(),
        session.snapshot.config.max_workers as usize,
    ) {
        TaskExtraction::NoFixes => {
            session.current_tasks = Vec::new();
            if session.snapshot.config.enabled_phases == "analysis-only" {
                complete(
                    session,
                    Some("Analysis complete. (Analysis-only mode)".to_string()),
                );
                ReviewPipelineStep::completed(Some(
                    "\n---\n**Analysis complete.** (Analysis-only mode)\n".to_string(),
                ))
            } else {
                ReviewPipelineStep::run_tests()
            }
        }
        TaskExtraction::Tasks(tasks) => {
            session.current_tasks = tasks.clone();
            ReviewPipelineStep::prepare_task_candidates(
                tasks,
                session
                    .snapshot
                    .scope
                    .as_ref()
                    .map(|scope| scope.files.clone())
                    .unwrap_or_default(),
                0,
            )
        }
        TaskExtraction::NoPayload(reason) => extraction_failure(session, reason),
        TaskExtraction::InvalidJson(reason) => {
            extraction_failure(session, format!("Could not parse task JSON: {reason}"))
        }
    }
}

fn on_prepare_task_candidates(
    session: &mut PipelineSession,
    callback: ReviewPipelineCallbackResult,
) -> ReviewPipelineStep {
    append_events(session, &callback.events);
    upsert_candidates(session, &callback.candidates);
    upsert_findings(session, &callback.promoted_findings);
    if session.snapshot.config.enabled_phases == "analysis-only" {
        complete(
            session,
            Some("Analysis complete. (Analysis-only mode)".to_string()),
        );
        return ReviewPipelineStep::completed(Some(
            "\n---\n**Analysis complete.** (Analysis-only mode)\n".to_string(),
        ));
    }
    if session.current_tasks.is_empty() {
        return ReviewPipelineStep::run_tests();
    }
    session.snapshot.current_round = 1;
    ReviewPipelineStep::fix_stage(
        session.current_tasks.clone(),
        1,
        session.resolved_scope.clone(),
        session.against_ref.clone(),
    )
}

fn on_fix_stage(
    session: &mut PipelineSession,
    callback: ReviewPipelineCallbackResult,
) -> ReviewPipelineStep {
    append_events(session, &callback.events);
    if let Some(reason) = callback.error {
        fail(session, reason.clone());
        return ReviewPipelineStep::failed(reason);
    }
    ReviewPipelineStep::run_tests()
}

fn on_run_tests(
    session: &mut PipelineSession,
    callback: ReviewPipelineCallbackResult,
) -> ReviewPipelineStep {
    session.snapshot.last_test_status = callback.test_status.clone();
    session.snapshot.stage = "testing".to_string();
    session.snapshot.phase = "testing".to_string();
    append_events(session, &callback.events);
    ReviewPipelineStep::scan_modified_files()
}

fn on_scan_modified_files(
    session: &mut PipelineSession,
    callback: ReviewPipelineCallbackResult,
) -> ReviewPipelineStep {
    if callback.files.is_empty() {
        if session.snapshot.last_test_status.as_deref() != Some("passed")
            && !session.snapshot.findings.is_empty()
        {
            fail(
                session,
                "Review finished with failing or inconclusive tests.".to_string(),
            );
            return ReviewPipelineStep::failed(
                "Review finished with failing or inconclusive tests.",
            );
        }
        if has_blocking_open_findings(session) {
            fail(
                session,
                "Review finished with remaining blocking findings.".to_string(),
            );
            return ReviewPipelineStep::failed("Review finished with remaining blocking findings.");
        }
        let pending_patch_ids = patchable_verified_finding_ids(&session.snapshot);
        if !pending_patch_ids.is_empty() {
            return ReviewPipelineStep::prepare_verified_patches(pending_patch_ids);
        }
        complete(session, None);
        return ReviewPipelineStep::completed(None);
    }
    ReviewPipelineStep::rereview(
        callback.files,
        session.snapshot.current_round.max(1),
        session.snapshot.config.max_workers,
    )
}

fn on_rereview(
    session: &mut PipelineSession,
    callback: ReviewPipelineCallbackResult,
) -> ReviewPipelineStep {
    if let Some(message) = callback.error {
        fail(session, format!("Re-review stream failed: {message}"));
        return ReviewPipelineStep::failed(format!("Re-review stream failed: {message}"));
    }
    let text = callback.text.unwrap_or_default();
    match classify_review_outcome(&text) {
        ReviewFindingsState::Clean => {
            mark_open_findings_fix_applied(session, &callback.files);
            if session.snapshot.last_test_status.as_deref() != Some("passed")
                && !session.snapshot.findings.is_empty()
            {
                fail(
                    session,
                    "Review finished with failing or inconclusive tests.".to_string(),
                );
                return ReviewPipelineStep::failed(
                    "Review finished with failing or inconclusive tests.",
                );
            }
            if has_blocking_open_findings(session) {
                fail(session, "Some blocking review findings remain open outside the files modified in the current round.".to_string());
                return ReviewPipelineStep::failed("Some blocking review findings remain open outside the files modified in the current round.");
            }
            let pending_patch_ids = patchable_verified_finding_ids(&session.snapshot);
            if !pending_patch_ids.is_empty() {
                return ReviewPipelineStep::prepare_verified_patches(pending_patch_ids);
            }
            complete(session, None);
            ReviewPipelineStep::completed(Some(
                "\n---\n**Multi-swarm code review complete.** Tests passing. Re-review clean.\n"
                    .to_string(),
            ))
        }
        ReviewFindingsState::Inconclusive(reason) => {
            fail(session, format!("Review ended inconclusively: {reason}"));
            ReviewPipelineStep::failed(format!("Review ended inconclusively: {reason}"))
        }
        ReviewFindingsState::Issues => {
            if session.snapshot.current_round >= session.snapshot.config.max_review_rounds {
                fail(
                    session,
                    "Review finished with remaining blocking findings.".to_string(),
                );
                return ReviewPipelineStep::failed(
                    "Review finished with remaining blocking findings.",
                );
            }
            let files = callback.files.clone();
            match parse_review_tasks(&text, &files, session.snapshot.config.max_workers as usize) {
                TaskExtraction::Tasks(tasks) if !tasks.is_empty() => {
                    session.snapshot.current_round += 1;
                    session.current_tasks = tasks.clone();
                    replace_open_findings_in_files(session, &files);
                    ReviewPipelineStep::prepare_task_candidates(
                        tasks,
                        files,
                        session.snapshot.current_round,
                    )
                }
                TaskExtraction::NoFixes | TaskExtraction::Tasks(_) => {
                    fail(
                        session,
                        "Re-review reported issues but produced no actionable follow-up tasks."
                            .to_string(),
                    );
                    ReviewPipelineStep::failed(
                        "Re-review reported issues but produced no actionable follow-up tasks.",
                    )
                }
                TaskExtraction::NoPayload(reason) | TaskExtraction::InvalidJson(reason) => {
                    fail(session, reason.clone());
                    ReviewPipelineStep::failed(reason)
                }
            }
        }
    }
}

fn on_prepare_verified_patches(
    session: &mut PipelineSession,
    callback: ReviewPipelineCallbackResult,
) -> ReviewPipelineStep {
    append_events(session, &callback.events);
    if let Some(reason) = callback.error {
        fail(session, format!("Patch preparation failed: {reason}"));
        return ReviewPipelineStep::failed(format!("Patch preparation failed: {reason}"));
    }
    if !callback.findings.is_empty() {
        replace_findings(session, callback.findings);
    }
    if !callback.patches.is_empty() {
        replace_patches(session, callback.patches);
    }
    let pending_patch_ids = patchable_verified_finding_ids(&session.snapshot);
    if !pending_patch_ids.is_empty() {
        fail(
            session,
            "Review finished without patch-ready artifacts for all verified findings.".to_string(),
        );
        return ReviewPipelineStep::failed(
            "Review finished without patch-ready artifacts for all verified findings.",
        );
    }
    complete(
        session,
        Some("Review completed with publish-ready findings.".to_string()),
    );
    ReviewPipelineStep::completed(Some(
        "\n---\n**Multi-swarm code review complete.** Tests passing. Patch previews ready.\n"
            .to_string(),
    ))
}

fn extraction_failure(session: &mut PipelineSession, reason: String) -> ReviewPipelineStep {
    session.last_extraction_failure = Some(reason.clone());
    fail(session, format!("Review task extraction failed: {reason}"));
    ReviewPipelineStep::failed(format!("Review task extraction failed: {reason}"))
}

fn sessions() -> &'static RwLock<HashMap<String, PipelineSession>> {
    SESSIONS.get_or_init(|| RwLock::new(HashMap::new()))
}

fn missing_session(session_id: &str) -> ReviewPipelineResponse {
    let placeholder = PipelineSession::new(
        session_id.to_string(),
        None,
        String::new(),
        super::models::ReviewPipelineConfig {
            max_workers: 1,
            max_review_rounds: 1,
            enabled_phases: "analysis-and-execution".to_string(),
            analysis_backend: "codex".to_string(),
            execution_backend: "codex".to_string(),
        },
        String::new(),
        None,
        "uncommitted".to_string(),
    );
    ReviewPipelineResponse::error(
        session_id.to_string(),
        placeholder.snapshot,
        "session_not_found",
        "pipeline session not found",
    )
}
