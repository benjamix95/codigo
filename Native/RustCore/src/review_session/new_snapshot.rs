use super::helpers::now_reference_seconds;
use super::models::{ReviewSessionResponse, ReviewSessionSnapshotNewRequest};
use serde_json::json;

pub fn new_snapshot(request: ReviewSessionSnapshotNewRequest) -> ReviewSessionResponse {
    if request.session_id.trim().is_empty() {
        return ReviewSessionResponse::error("invalid_session_id", "sessionId is required");
    }
    let config = request.config.unwrap_or_else(|| {
        json!({
            "maxWorkers": 6,
            "maxRounds": 3,
            "analysisBackend": "codex",
            "executionBackend": "codex",
            "analysisOnly": false
        })
    });
    let now = now_reference_seconds();
    ReviewSessionResponse::success(json!({
        "sessionId": request.session_id,
        "conversationId": request.conversation_id,
        "mutationSequence": 0,
        "phase": "idle",
        "stage": "idle",
        "findings": [],
        "candidates": [],
        "patches": [],
        "events": [],
        "config": config,
        "scope": null,
        "workspacePath": null,
        "currentRound": 0,
        "activeWorkerCount": 0,
        "startedAt": null,
        "completedAt": null,
        "analysisCompletedAt": null,
        "lastError": null,
        "currentJobId": null,
        "lastTestStatus": null,
        "audit": {
            "toolCoverage": {},
            "toolDurationsMs": {},
            "toolFindingsCounts": {},
            "toolAdapters": {}
        },
        "outcome": {
            "summary": "No review outcome available yet.",
            "verifiedFindings": 0,
            "falsePositives": 0,
            "patchesReady": 0,
            "patchesApplied": 0,
            "prsOpened": 0,
            "mergedPatches": 0,
            "conflictsDetected": 0,
            "manualActionRequired": false,
            "testsStatus": null,
            "generatedAt": 0.0
        },
        "verifiedFindings": null,
        "phaseLedger": [],
        "fileLedger": [],
        "lastUpdatedAt": now
    }))
}
