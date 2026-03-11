use super::models::{
    CommandRecord, ReviewMCPCommandQueueRequest, ReviewMCPCommandQueueResponse, ReviewMCPIndexResponse,
    ReviewMCPIndexRequest, ReviewSnapshotIndexRecord, ReviewSnapshotRecord,
};
use std::collections::HashMap;

const REVIEW_STALE_TIMEOUT: f64 = 120.0;
const BUGHUNTER_STALE_TIMEOUT: f64 = 3605.0;

pub fn enqueue_review_command(request: ReviewMCPCommandQueueRequest) -> ReviewMCPCommandQueueResponse {
    let unique_start = request.operation == "enqueue_unique_review_start";
    enqueue_command(request, unique_start)
}

pub fn enqueue_bughunter_command(request: ReviewMCPCommandQueueRequest) -> ReviewMCPCommandQueueResponse {
    enqueue_command(request, false)
}

fn enqueue_command(
    request: ReviewMCPCommandQueueRequest,
    unique_start: bool,
) -> ReviewMCPCommandQueueResponse {
    let mut commands = request.commands;
    let action = request.action.unwrap_or_default();
    let session_id = sanitize_session_id(request.session_id);
    let run_id = non_empty(request.run_id);
    let payload = request.payload.into_iter().filter(|(key, _)| !key.is_empty()).collect::<HashMap<_, _>>();

    if unique_start && action == "start" {
        if let Some(ref session_id) = session_id {
            let duplicate = commands.iter().any(|command| {
                command.action == "start"
                    && command.session_id.as_deref() == Some(session_id.as_str())
                    && matches!(command.status.as_str(), "pending" | "processing")
            });
            if duplicate {
                return ReviewMCPCommandQueueResponse::err("sessionAlreadyQueued", commands);
            }
        }
    }

    let id = format!(
        "{}-{}",
        request.queue_kind,
        request.now_reference_seconds.to_bits()
    );
    let command = CommandRecord {
        id,
        action,
        session_id,
        run_id,
        conversation_id: non_empty(request.conversation_id),
        payload,
        created_at_reference_seconds: request.now_reference_seconds,
        updated_at_reference_seconds: request.now_reference_seconds,
        status: "pending".to_string(),
        result_message: None,
    };
    commands.push(command.clone());
    ReviewMCPCommandQueueResponse::ok(commands, Some(command), Vec::new())
}

pub fn claim_commands(request: ReviewMCPCommandQueueRequest) -> ReviewMCPCommandQueueResponse {
    let mut commands = request.commands;
    let timeout = if request.queue_kind == "bughunter" {
        BUGHUNTER_STALE_TIMEOUT
    } else {
        REVIEW_STALE_TIMEOUT
    };

    for command in &mut commands {
        let is_pending = command.status == "pending";
        let is_stale_processing = command.status == "processing"
            && request.now_reference_seconds - command.updated_at_reference_seconds >= timeout;
        if is_pending || is_stale_processing {
            command.status = "processing".to_string();
            command.updated_at_reference_seconds = request.now_reference_seconds;
            command.result_message = None;
        }
    }

    let mut claimed = commands
        .iter()
        .filter(|command| command.status == "processing" && command.updated_at_reference_seconds == request.now_reference_seconds)
        .cloned()
        .collect::<Vec<_>>();
    claimed.sort_by(|lhs, rhs| {
            lhs.created_at_reference_seconds
                .partial_cmp(&rhs.created_at_reference_seconds)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| lhs.id.cmp(&rhs.id))
        });
    ReviewMCPCommandQueueResponse::ok(commands, claimed.first().cloned(), claimed)
}

pub fn mark_command(request: ReviewMCPCommandQueueRequest) -> ReviewMCPCommandQueueResponse {
    let mut commands = request.commands;
    let Some(command_id) = request.command_id else {
        return ReviewMCPCommandQueueResponse::err("missing command id", commands);
    };
    let Some(status) = request.status else {
        return ReviewMCPCommandQueueResponse::err("missing status", commands);
    };
    if let Some(command) = commands.iter_mut().find(|command| command.id == command_id) {
        command.status = status;
        command.result_message = request.result_message;
        command.updated_at_reference_seconds = request.now_reference_seconds;
        let updated = command.clone();
        return ReviewMCPCommandQueueResponse::ok(commands, Some(updated), Vec::new());
    }
    ReviewMCPCommandQueueResponse::err("command not found", commands)
}

pub fn heartbeat_command(request: ReviewMCPCommandQueueRequest) -> ReviewMCPCommandQueueResponse {
    let mut commands = request.commands;
    let Some(command_id) = request.command_id else {
        return ReviewMCPCommandQueueResponse::err("missing command id", commands);
    };
    if let Some(command) = commands.iter_mut().find(|command| command.id == command_id && command.status == "processing") {
        command.updated_at_reference_seconds = request.now_reference_seconds;
        let updated = command.clone();
        return ReviewMCPCommandQueueResponse::ok(commands, Some(updated), Vec::new());
    }
    ReviewMCPCommandQueueResponse::ok(commands, None, Vec::new())
}

pub fn build_review_index(request: ReviewMCPIndexRequest) -> ReviewMCPIndexResponse {
    let mut snapshots = request.review_snapshots;
    snapshots.sort_by(|lhs, rhs| {
        rhs.updated_at_reference_seconds
            .partial_cmp(&lhs.updated_at_reference_seconds)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| rhs.session_id.cmp(&lhs.session_id))
    });

    let mut latest_by_conversation = HashMap::new();
    for snapshot in &snapshots {
        if let Some(conversation_id) = &snapshot.conversation_id {
            latest_by_conversation
                .entry(conversation_id.clone())
                .or_insert_with(|| snapshot.session_id.clone());
        }
    }

    ReviewMCPIndexResponse {
        schema_version: 1,
        latest_session_id: snapshots.first().map(|snapshot| snapshot.session_id.clone()),
        latest_session_id_by_conversation: latest_by_conversation,
        sessions: snapshots.into_iter().map(index_record).collect(),
    }
}

fn index_record(snapshot: ReviewSnapshotRecord) -> ReviewSnapshotIndexRecord {
    ReviewSnapshotIndexRecord {
        session_id: snapshot.session_id,
        conversation_id: snapshot.conversation_id,
        phase: snapshot.phase,
        stage: snapshot.stage,
        findings_count: snapshot.findings_count,
        open_findings_count: snapshot.open_findings_count,
        current_round: snapshot.current_round,
        active_worker_count: snapshot.active_worker_count,
        scope_type: snapshot.scope_type,
        scope_ref: snapshot.scope_ref,
        started_at_reference_seconds: snapshot.started_at_reference_seconds,
        updated_at_reference_seconds: snapshot.updated_at_reference_seconds,
        is_active: snapshot.is_active,
    }
}

fn sanitize_session_id(session_id: Option<String>) -> Option<String> {
    let session_id = non_empty(session_id.map(|value| value.trim().to_string()));
    let session_id = session_id?;
    if session_id.len() > 128 {
        return None;
    }
    let mut chars = session_id.chars();
    let Some(first) = chars.next() else { return None };
    if !first.is_ascii_alphanumeric() {
        return None;
    }
    if chars.all(|ch| ch.is_ascii_alphanumeric() || ch == '-' || ch == '_') {
        Some(session_id)
    } else {
        None
    }
}

fn non_empty(value: Option<String>) -> Option<String> {
    value.and_then(|value| {
        let trimmed = value.trim().to_string();
        if trimmed.is_empty() { None } else { Some(trimmed) }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn enqueue_unique_review_start_rejects_duplicate_processing_session() {
        let request = ReviewMCPCommandQueueRequest {
            schema_version: 1,
            operation: "enqueue_unique_review_start".to_string(),
            queue_kind: "review".to_string(),
            commands: vec![CommandRecord {
                id: "existing".to_string(),
                action: "start".to_string(),
                session_id: Some("session-1".to_string()),
                run_id: None,
                conversation_id: None,
                payload: HashMap::new(),
                created_at_reference_seconds: 1.0,
                updated_at_reference_seconds: 1.0,
                status: "processing".to_string(),
                result_message: None,
            }],
            command_id: None,
            action: Some("start".to_string()),
            session_id: Some("session-1".to_string()),
            run_id: None,
            conversation_id: None,
            status: None,
            result_message: None,
            now_reference_seconds: 10.0,
            payload: HashMap::new(),
        };

        let response = enqueue_review_command(request);
        assert!(response.is_error);
    }

    #[test]
    fn claim_marks_stale_processing_commands() {
        let request = ReviewMCPCommandQueueRequest {
            schema_version: 1,
            operation: "claim".to_string(),
            queue_kind: "review".to_string(),
            commands: vec![CommandRecord {
                id: "existing".to_string(),
                action: "configure".to_string(),
                session_id: Some("session-1".to_string()),
                run_id: None,
                conversation_id: None,
                payload: HashMap::new(),
                created_at_reference_seconds: 1.0,
                updated_at_reference_seconds: 1.0,
                status: "processing".to_string(),
                result_message: None,
            }],
            command_id: None,
            action: None,
            session_id: None,
            run_id: None,
            conversation_id: None,
            status: None,
            result_message: None,
            now_reference_seconds: 500.0,
            payload: HashMap::new(),
        };
        let response = claim_commands(request);
        assert_eq!(response.command.as_ref().map(|command| command.id.as_str()), Some("existing"));
    }
}
