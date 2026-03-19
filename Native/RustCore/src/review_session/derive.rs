use super::helpers::{build_outcome, is_open_status};
use super::models::{ReviewSessionActionRequest, ReviewSessionProjectionResponse};
use serde_json::{json, Value};
use std::collections::BTreeMap;

pub fn derive_view(request: ReviewSessionActionRequest) -> ReviewSessionProjectionResponse {
    let findings = request
        .snapshot
        .get("findings")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();

    let mut by_file: BTreeMap<String, usize> = BTreeMap::new();
    let mut by_severity: BTreeMap<String, usize> = BTreeMap::new();
    for finding in &findings {
        if let Some(file) = finding.get("filePath").and_then(Value::as_str) {
            *by_file.entry(file.to_string()).or_default() += 1;
        }
        if let Some(severity) = finding.get("severity").and_then(Value::as_str) {
            *by_severity.entry(severity.to_string()).or_default() += 1;
        }
    }

    let open_findings = findings
        .iter()
        .filter(|item| item.get("status").and_then(Value::as_str).map(is_open_status).unwrap_or(false))
        .count();

    ReviewSessionProjectionResponse::success(json!({
        "statusSummary": request.snapshot.get("outcome")
            .cloned()
            .unwrap_or_else(|| build_outcome(&request.snapshot, None))
            .get("summary")
            .cloned()
            .unwrap_or_else(|| Value::String(format!("{} findings", findings.len()))),
        "findingsByFile": by_file,
        "findingsBySeverity": by_severity,
        "openFindingsCount": open_findings,
        "outcome": build_outcome(&request.snapshot, None),
    }))
}
