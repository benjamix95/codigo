use crate::review_value::{get_bool, get_str};
use serde_json::Value;
use std::collections::HashMap;

pub fn merge_history(primary: Vec<Value>, fallback: Vec<Value>) -> Vec<Value> {
    let mut merged: HashMap<String, Value> = primary
        .into_iter()
        .filter_map(|record| Some((get_str(&record, "findingId")?.to_string(), record)))
        .collect();

    for record in fallback {
        let Some(finding_id) = get_str(&record, "findingId") else { continue };
        let replace = merged
            .get(finding_id)
            .map(|existing| updated_at(&record) > updated_at(existing))
            .unwrap_or(true);
        if replace {
            merged.insert(finding_id.to_string(), record);
        }
    }

    let mut values: Vec<Value> = merged.into_values().collect();
    values.sort_by(|lhs, rhs| compare_history(lhs, rhs));
    values
}

fn compare_history(lhs: &Value, rhs: &Value) -> std::cmp::Ordering {
    match (get_bool(lhs, "resumeEligible"), get_bool(rhs, "resumeEligible")) {
        (true, false) => std::cmp::Ordering::Less,
        (false, true) => std::cmp::Ordering::Greater,
        _ => updated_at(rhs)
            .partial_cmp(&updated_at(lhs))
            .unwrap_or(std::cmp::Ordering::Equal),
    }
}

fn updated_at(value: &Value) -> f64 {
    value.get("updatedAt").and_then(Value::as_f64).unwrap_or(0.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn merge_history_prefers_newer_and_resume_eligible() {
        let merged = merge_history(
            vec![json!({"findingId": "a", "resumeEligible": false, "updatedAt": 1.0})],
            vec![
                json!({"findingId": "a", "resumeEligible": true, "updatedAt": 2.0}),
                json!({"findingId": "b", "resumeEligible": false, "updatedAt": 3.0}),
            ],
        );
        assert_eq!(merged[0]["findingId"].as_str(), Some("a"));
        assert_eq!(merged[1]["findingId"].as_str(), Some("b"));
    }
}
