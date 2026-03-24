use crate::review_value::normalize;
use serde_json::{json, Value};
use std::collections::HashSet;

pub fn merge_chat_findings(existing: &[Value], incoming: &[Value]) -> Value {
    let mut seen = existing.iter().map(finding_key).collect::<HashSet<_>>();
    let mut merged = existing.to_vec();
    let mut inserted = 0_i64;

    for finding in incoming {
        let key = finding_key(finding);
        if seen.insert(key) {
            merged.push(finding.clone());
            inserted += 1;
        }
    }

    json!({
        "findings": merged,
        "insertedCount": inserted,
    })
}

fn finding_key(finding: &Value) -> String {
    let file = finding
        .get("filePath")
        .and_then(Value::as_str)
        .map(normalize)
        .unwrap_or_default();
    let line = finding
        .get("lineNumber")
        .and_then(Value::as_i64)
        .unwrap_or(0);
    let category = finding
        .get("category")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let message = finding
        .get("message")
        .and_then(Value::as_str)
        .map(normalize)
        .unwrap_or_default();
    [file, line.to_string(), category.to_string(), message].join("|")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn merge_chat_findings_deduplicates_on_panel_key() {
        let existing = vec![json!({
            "id": "f-1",
            "filePath": "Sources/App/Main.swift",
            "lineNumber": 42,
            "category": "correctness",
            "message": "Missing guard before dereferencing the session"
        })];
        let incoming = vec![json!({
            "id": "f-2",
            "filePath": "sources/app/main.swift",
            "lineNumber": 42,
            "category": "correctness",
            "message": "Missing guard before dereferencing the session"
        })];

        let merged = merge_chat_findings(&existing, &incoming);
        assert_eq!(merged["insertedCount"].as_i64(), Some(0));
        assert_eq!(
            merged["findings"].as_array().map(|items| items.len()),
            Some(1)
        );
    }

    #[test]
    fn merge_chat_findings_reports_inserted_count_for_new_finding() {
        let existing = vec![json!({
            "id": "f-1",
            "filePath": "Sources/App/Main.swift",
            "lineNumber": 42,
            "category": "correctness",
            "message": "Missing guard before dereferencing the session"
        })];
        let incoming = vec![json!({
            "id": "f-2",
            "filePath": "Sources/App/Other.swift",
            "lineNumber": 13,
            "category": "regression",
            "message": "Retry emits a duplicate terminal event"
        })];

        let merged = merge_chat_findings(&existing, &incoming);
        assert_eq!(merged["insertedCount"].as_i64(), Some(1));
        assert_eq!(
            merged["findings"].as_array().map(|items| items.len()),
            Some(2)
        );
    }
}
