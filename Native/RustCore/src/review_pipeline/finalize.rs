use super::models::ReviewPipelineSnapshot;
use serde_json::Value;
use std::collections::{HashMap, HashSet};

pub fn publish_ready_finding_ids(snapshot: &ReviewPipelineSnapshot) -> HashSet<String> {
    let verified_ids = verified_queue_ids(snapshot);
    let patches_by_finding = snapshot
        .patches
        .iter()
        .filter_map(|patch| {
            patch
                .get("findingId")
                .and_then(Value::as_str)
                .map(|id| (id.to_string(), patch))
        })
        .collect::<HashMap<_, _>>();

    snapshot
        .findings
        .iter()
        .filter_map(|finding| {
            let finding_id = finding.get("id").and_then(Value::as_str)?;
            if !verified_ids.contains(finding_id) || !is_verified_finding(finding) {
                return None;
            }
            let patch_id = finding.get("patchArtifactId").and_then(Value::as_str)?;
            let patch = patches_by_finding.get(finding_id)?;
            let patch_status = patch.get("status").and_then(Value::as_str)?;
            let verify_status = patch.get("verifyStatus").and_then(Value::as_str)?;
            if patch.get("id").and_then(Value::as_str) != Some(patch_id)
                || verify_status != "verified"
            {
                return None;
            }
            matches!(patch_status, "verified" | "applied" | "prOpened" | "merged")
                .then(|| finding_id.to_string())
        })
        .collect()
}

pub fn patchable_verified_finding_ids(snapshot: &ReviewPipelineSnapshot) -> Vec<String> {
    let publish_ready = publish_ready_finding_ids(snapshot);
    let verified_ids = verified_queue_ids(snapshot);
    snapshot
        .findings
        .iter()
        .filter_map(|finding| {
            let finding_id = finding.get("id").and_then(Value::as_str)?;
            if publish_ready.contains(finding_id) {
                return None;
            }
            if (!verified_ids.is_empty() && !verified_ids.contains(finding_id))
                || !is_verified_finding(finding)
            {
                return None;
            }
            Some(finding_id.to_string())
        })
        .collect()
}

fn verified_queue_ids(snapshot: &ReviewPipelineSnapshot) -> HashSet<String> {
    snapshot
        .verified_findings
        .as_ref()
        .and_then(|value| value.pointer("/projectionSnapshot/verifiedQueue"))
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|item| item.get("id").and_then(Value::as_str))
        .map(ToString::to_string)
        .collect()
}

fn is_verified_finding(finding: &Value) -> bool {
    !finding.get("verifiedAt").unwrap_or(&Value::Null).is_null()
        || !finding
            .get("verificationReport")
            .unwrap_or(&Value::Null)
            .is_null()
}
