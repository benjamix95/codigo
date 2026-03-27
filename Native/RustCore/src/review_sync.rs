use crate::review_identity::{prepare, similarity_score, IdentityIndex};
use crate::review_projection::build_projection;
use crate::review_value::{set_optional_string, set_string_array};
use serde_json::Value;

pub fn sync_findings(
    mut findings: Vec<Value>,
    trace_log: Vec<String>,
) -> Result<(Vec<Value>, Value), String> {
    findings.sort_by(|lhs, rhs| {
        created_at(lhs)
            .partial_cmp(&created_at(rhs))
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let mut index = IdentityIndex::default();
    let mut output = Vec::with_capacity(findings.len());
    for mut finding in findings {
        let identity = prepare(&finding);
        if identity.finding_id.is_empty() {
            return Err("finding missing id".to_string());
        }
        let mut inserted_identity = identity.clone();
        if let Some(existing_id) = index.exact_duplicate_id(&identity) {
            set_string_array(
                &mut finding,
                "possibleDuplicateOf",
                vec![existing_id.clone()],
            );
            set_optional_string(
                &mut finding,
                "mergedIntoFindingId",
                Some(existing_id.clone()),
            );
            set_optional_string(&mut finding, "recurrenceGroupId", Some(existing_id));
            inserted_identity = prepare(&finding);
        } else {
            let best = index
                .candidates(&identity)
                .into_iter()
                .map(|candidate| {
                    let score = similarity_score(&identity, &candidate);
                    (candidate.finding_id, score)
                })
                .filter(|(_, score)| *score >= 0.75)
                .max_by(|lhs, rhs| {
                    lhs.1
                        .partial_cmp(&rhs.1)
                        .unwrap_or(std::cmp::Ordering::Equal)
                });
            if let Some((existing_id, _)) = best {
                set_string_array(
                    &mut finding,
                    "possibleDuplicateOf",
                    vec![existing_id.clone()],
                );
                set_optional_string(&mut finding, "recurrenceGroupId", Some(existing_id));
                inserted_identity = prepare(&finding);
            }
        }
        index.insert(inserted_identity);
        output.push(finding);
    }

    let projection = build_projection(&output, &trace_log);
    Ok((output, projection))
}

fn created_at(finding: &Value) -> f64 {
    finding
        .get("createdAt")
        .and_then(Value::as_f64)
        .unwrap_or(0.0)
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
        let (findings, projection) =
            sync_findings(vec![first, second], vec!["a".to_string()]).unwrap();
        assert_eq!(findings.len(), 2);
        assert_eq!(projection["duplicatesCount"].as_i64(), Some(1));
        assert_eq!(
            findings[1]["possibleDuplicateOf"].as_array().unwrap()[0].as_str(),
            Some("candidate-1")
        );
    }
}
