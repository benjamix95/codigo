use crate::review_value::{get_str, normalize};
use serde_json::{json, Value};

pub fn build_projection(findings: &[Value], trace_log: &[String]) -> Value {
    let items: Vec<Value> = findings.iter().map(list_item_projection).collect();
    let candidates: Vec<Value> = items
        .iter()
        .filter(|item| matches!(get_str(item, "status"), Some("candidate" | "verifying")))
        .cloned()
        .collect();
    let verified: Vec<Value> = items
        .iter()
        .filter(|item| {
            matches!(
                get_str(item, "status"),
                Some(
                    "verified"
                        | "patch_preparing"
                        | "patch_prepared"
                        | "patch_reviewed"
                        | "patch_applied"
                        | "revalidating"
                        | "fixed_verified"
                        | "fix_failed"
                        | "rollback_applied"
                        | "closed"
                )
            )
        })
        .cloned()
        .collect();
    let duplicates_count = items
        .iter()
        .filter(|item| {
            !item
                .get("duplicateOf")
                .and_then(Value::as_array)
                .is_none_or(|value| value.is_empty())
                || !item
                    .get("mergedIntoFindingId")
                    .map(Value::is_null)
                    .unwrap_or(true)
        })
        .count();
    let stale_candidates_count = candidates
        .iter()
        .filter(|item| get_str(item, "staleStatus").unwrap_or("active") != "active")
        .count();

    json!({
        "candidateQueue": sort_items(candidates),
        "verifiedQueue": sort_items(verified),
        "duplicatesCount": duplicates_count,
        "staleCandidatesCount": stale_candidates_count,
        "traceSnippets": trace_log.iter().rev().take(20).cloned().collect::<Vec<_>>().into_iter().rev().collect::<Vec<_>>()
    })
}

fn list_item_projection(finding: &Value) -> Value {
    json!({
        "id": get_str(finding, "id").unwrap_or_default(),
        "title": get_str(finding, "title").unwrap_or_default(),
        "domain": get_str(finding, "domain").unwrap_or("bug"),
        "status": get_str(finding, "status").unwrap_or("candidate"),
        "staleStatus": get_str(finding, "staleStatus").unwrap_or("active"),
        "severity": get_str(finding, "severity").unwrap_or("medium"),
        "filePath": get_str(finding, "filePath").unwrap_or_default(),
        "lineStart": finding.get("lineStart").cloned().unwrap_or(Value::Null),
        "duplicateOf": finding.get("possibleDuplicateOf").cloned().unwrap_or_else(|| json!([])),
        "mergedIntoFindingId": finding.get("mergedIntoFindingId").cloned().unwrap_or(Value::Null),
        "recurrenceGroupId": finding.get("recurrenceGroupId").cloned().unwrap_or(Value::Null)
    })
}

fn sort_items(mut items: Vec<Value>) -> Vec<Value> {
    items.sort_by(|lhs, rhs| {
        normalize(get_str(lhs, "id").unwrap_or_default())
            .cmp(&normalize(get_str(rhs, "id").unwrap_or_default()))
    });
    items
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn builds_projection_queues_and_duplicate_count() {
        let projection = build_projection(
            &[
                json!({"id":"a","title":"A","domain":"bug","status":"candidate","staleStatus":"active","severity":"medium","filePath":"A.swift","possibleDuplicateOf":[]}),
                json!({"id":"b","title":"B","domain":"bug","status":"verified","staleStatus":"active","severity":"high","filePath":"B.swift","possibleDuplicateOf":["a"]}),
            ],
            &["trace-a".to_string(), "trace-b".to_string()],
        );
        assert_eq!(projection["candidateQueue"].as_array().unwrap().len(), 1);
        assert_eq!(projection["verifiedQueue"].as_array().unwrap().len(), 1);
        assert_eq!(projection["duplicatesCount"].as_i64(), Some(1));
    }
}
