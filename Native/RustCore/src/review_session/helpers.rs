use serde_json::{json, Map, Value};
use std::time::{SystemTime, UNIX_EPOCH};

pub fn object_mut<'a>(
    value: &'a mut Value,
    key: &str,
) -> Result<&'a mut Map<String, Value>, String> {
    value
        .get_mut(key)
        .and_then(Value::as_object_mut)
        .ok_or_else(|| format!("Snapshot {key} is missing"))
}

pub fn array_mut<'a>(value: &'a mut Value, key: &str) -> Result<&'a mut Vec<Value>, String> {
    value
        .get_mut(key)
        .and_then(Value::as_array_mut)
        .ok_or_else(|| format!("Snapshot {key} is missing"))
}

pub fn array<'a>(value: &'a Value, key: &str) -> Result<&'a Vec<Value>, String> {
    value
        .get(key)
        .and_then(Value::as_array)
        .ok_or_else(|| format!("Snapshot {key} is missing"))
}

pub fn string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(ToString::to_string)
}

pub fn now_reference_seconds() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
        - 978_307_200.0
}

pub fn scope_description(scope: &Value) -> String {
    let file_count = scope
        .get("files")
        .and_then(Value::as_array)
        .map(|items| items.len())
        .unwrap_or(0);
    match scope
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or("uncommitted")
    {
        "uncommitted" => format!("uncommitted changes ({file_count} files)"),
        "staged" => format!("staged changes ({file_count} files)"),
        "workspace" => format!("workspace source files ({file_count} files)"),
        "against_ref" => format!(
            "vs {} ({file_count} files)",
            scope
                .get("ref")
                .and_then(Value::as_str)
                .unwrap_or("unknown")
        ),
        _ => format!("review scope ({file_count} files)"),
    }
}

pub fn is_open_status(status: &str) -> bool {
    matches!(
        status,
        "open" | "patch_preparing" | "patch_ready" | "patch_applying" | "blocked"
    )
}

pub fn event(kind: &str, detail: Option<String>, metadata: Value, timestamp: f64) -> Value {
    let metadata = metadata.as_object().cloned().unwrap_or_default();
    Value::Object(Map::from_iter([
        (
            "id".to_string(),
            Value::String(format!("rust-event-{kind}-{timestamp:.6}")),
        ),
        ("type".to_string(), Value::String(kind.to_string())),
        ("timestamp".to_string(), json!(timestamp)),
        (
            "detail".to_string(),
            detail.map(Value::String).unwrap_or(Value::Null),
        ),
        ("metadata".to_string(), Value::Object(metadata)),
    ]))
}

pub fn build_outcome(snapshot: &Value, summary_override: Option<String>) -> Value {
    let findings = snapshot
        .get("findings")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let candidates = snapshot
        .get("candidates")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let patches = snapshot
        .get("patches")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let verified_findings = findings.len();
    let false_positives = candidates
        .iter()
        .filter(|item| {
            item.get("verificationStatus").and_then(Value::as_str)
                == Some("rejected_false_positive")
        })
        .count();
    let patches_ready = patches
        .iter()
        .filter(|item| {
            matches!(
                item.get("status").and_then(Value::as_str),
                Some("verified" | "draft")
            )
        })
        .count();
    let patches_applied = patches
        .iter()
        .filter(|item| item.get("status").and_then(Value::as_str) == Some("applied"))
        .count();
    let prs_opened = patches
        .iter()
        .filter(|item| {
            matches!(item.get("prStatus").and_then(Value::as_str), Some("opened"))
                || item.get("status").and_then(Value::as_str) == Some("pr_opened")
        })
        .count();
    let merged_patches = patches
        .iter()
        .filter(|item| {
            matches!(
                item.get("mergeStatus").and_then(Value::as_str),
                Some("merged")
            ) || item.get("status").and_then(Value::as_str) == Some("merged")
        })
        .count();
    let conflicts_detected = patches
        .iter()
        .map(|item| {
            item.get("conflicts")
                .and_then(Value::as_array)
                .map(|items| items.len())
                .unwrap_or(0)
        })
        .sum::<usize>();
    let manual_action_required = patches.iter().any(|item| {
        matches!(
            item.get("status").and_then(Value::as_str),
            Some("conflict" | "apply_failed")
        ) || item.get("mergeStatus").and_then(Value::as_str) == Some("blocked")
    }) || candidates
        .iter()
        .any(|item| item.get("verificationStatus").and_then(Value::as_str) == Some("inconclusive"));
    let tests_status = snapshot
        .get("lastTestStatus")
        .cloned()
        .unwrap_or(Value::Null);
    json!({
        "summary": summary_override.unwrap_or_else(|| format!(
            "{} verified finding(s), {} false positive(s), {} patch(es) applied.",
            verified_findings, false_positives, patches_applied
        )),
        "verifiedFindings": verified_findings,
        "falsePositives": false_positives,
        "patchesReady": patches_ready,
        "patchesApplied": patches_applied,
        "prsOpened": prs_opened,
        "mergedPatches": merged_patches,
        "conflictsDetected": conflicts_detected,
        "manualActionRequired": manual_action_required,
        "testsStatus": tests_status,
        "generatedAt": now_reference_seconds(),
    })
}
