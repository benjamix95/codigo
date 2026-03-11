use crate::review_identity::{prepare, similarity_score, IdentityIndex};
use crate::review_value::{get_str, normalize, set_optional_string, set_string_array};
use serde_json::{json, Value};

pub fn sync_findings(mut findings: Vec<Value>, trace_log: Vec<String>) -> Result<(Vec<Value>, Value), String> {
    findings.sort_by(|lhs, rhs| created_at(lhs).partial_cmp(&created_at(rhs)).unwrap_or(std::cmp::Ordering::Equal));

    let mut index = IdentityIndex::default();
    let mut output = Vec::with_capacity(findings.len());
    for mut finding in findings {
        let identity = prepare(&finding);
        if identity.finding_id.is_empty() {
            return Err("finding missing id".to_string());
        }
        if let Some(existing_id) = index.exact_duplicate_id(&identity) {
            set_string_array(&mut finding, "possibleDuplicateOf", vec![existing_id.clone()]);
            set_optional_string(&mut finding, "mergedIntoFindingId", Some(existing_id.clone()));
            set_optional_string(&mut finding, "recurrenceGroupId", Some(existing_id));
        } else {
            let best = index
                .candidates(&identity)
                .into_iter()
                .map(|candidate| {
                    let score = similarity_score(&identity, &candidate);
                    (candidate.finding_id, score)
                })
                .filter(|(_, score)| *score >= 0.75)
                .max_by(|lhs, rhs| lhs.1.partial_cmp(&rhs.1).unwrap_or(std::cmp::Ordering::Equal));
            if let Some((existing_id, _)) = best {
                set_string_array(&mut finding, "possibleDuplicateOf", vec![existing_id.clone()]);
                set_optional_string(&mut finding, "recurrenceGroupId", Some(existing_id));
            }
        }
        index.insert(prepare(&finding));
        output.push(finding);
    }

    let projection = build_projection(&output, trace_log);
    Ok((output, projection))
}

fn build_projection(findings: &[Value], trace_log: Vec<String>) -> Value {
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
            !item.get("duplicateOf").and_then(Value::as_array).unwrap_or(&Vec::new()).is_empty()
                || !item.get("mergedIntoFindingId").map(Value::is_null).unwrap_or(true)
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
        "traceSnippets": trace_log.into_iter().rev().take(20).collect::<Vec<_>>().into_iter().rev().collect::<Vec<_>>()
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
    items.sort_by(|lhs, rhs| normalize(get_str(lhs, "id").unwrap_or_default()).cmp(&normalize(get_str(rhs, "id").unwrap_or_default())));
    items
}

fn created_at(finding: &Value) -> f64 {
    finding.get("createdAt").and_then(Value::as_f64).unwrap_or(0.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn sync_marks_duplicates_and_projection() {
        let first = json!({
            "id": "candidate-1",
            "domain": "bug",
            "title": "Potential nil access",
            "summary": "fatalError()",
            "category": "correctness",
            "severity": "medium",
            "status": "candidate",
            "filePath": "Sources/App.swift",
            "lineStart": 30,
            "findingFingerprint": "fingerprint-1",
            "staleStatus": "active",
            "createdAt": 1.0
        });
        let second = json!({
            "id": "candidate-2",
            "domain": "bug",
            "title": "Potential nil access",
            "summary": "fatalError()",
            "category": "correctness",
            "severity": "medium",
            "status": "candidate",
            "filePath": "Sources/App.swift",
            "lineStart": 31,
            "findingFingerprint": "fingerprint-2",
            "staleStatus": "active",
            "createdAt": 2.0
        });
        let (findings, projection) = sync_findings(vec![first, second], vec!["a".to_string()]).unwrap();
        assert_eq!(findings.len(), 2);
        assert_eq!(projection["duplicatesCount"].as_i64(), Some(1));
        assert_eq!(
            findings[1]["possibleDuplicateOf"].as_array().unwrap()[0].as_str(),
            Some("candidate-1")
        );
    }
}
