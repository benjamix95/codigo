mod live;
mod live_inputs;
mod snapshot;

pub use live::derive_history_live_state;
pub use snapshot::derive_historical_findings_from_snapshot;

use serde_json::Value;
use std::collections::HashMap;

pub fn shape_historical_findings(records: Vec<Value>) -> Vec<Value> {
    let mut merged: HashMap<String, Value> = HashMap::new();
    for mut record in records {
        normalize_timeline(&mut record);
        let Some(finding_id) = record.get("findingId").and_then(Value::as_str) else {
            continue;
        };
        let replace = merged
            .get(finding_id)
            .map(|existing| updated_at(&record) > updated_at(existing))
            .unwrap_or(true);
        if replace {
            merged.insert(finding_id.to_string(), record);
        }
    }
    let mut items = merged.into_values().collect::<Vec<_>>();
    items.sort_by(compare_records);
    items
}

fn normalize_timeline(record: &mut Value) {
    if let Some(timeline) = record.get_mut("timeline").and_then(Value::as_array_mut) {
        timeline.sort_by(|lhs, rhs| {
            let lhs_created = lhs
                .get("createdAt")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let rhs_created = rhs
                .get("createdAt")
                .and_then(Value::as_str)
                .unwrap_or_default();
            lhs_created.cmp(rhs_created)
        });
    }
}

fn compare_records(lhs: &Value, rhs: &Value) -> std::cmp::Ordering {
    match (resume_eligible(lhs), resume_eligible(rhs)) {
        (true, false) => std::cmp::Ordering::Less,
        (false, true) => std::cmp::Ordering::Greater,
        _ => updated_at(rhs)
            .partial_cmp(&updated_at(lhs))
            .unwrap_or(std::cmp::Ordering::Equal),
    }
}

fn resume_eligible(value: &Value) -> bool {
    value
        .get("resumeEligible")
        .and_then(Value::as_bool)
        .unwrap_or(false)
}

fn updated_at(value: &Value) -> f64 {
    value
        .get("updatedAt")
        .and_then(Value::as_f64)
        .unwrap_or(0.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn sorts_resume_first_then_updated_desc() {
        let shaped = shape_historical_findings(vec![
            json!({"findingId":"a","resumeEligible":false,"updatedAt":1.0,"timeline":[]}),
            json!({"findingId":"b","resumeEligible":true,"updatedAt":0.5,"timeline":[]}),
            json!({"findingId":"c","resumeEligible":true,"updatedAt":2.0,"timeline":[]}),
        ]);
        assert_eq!(shaped[0]["findingId"].as_str(), Some("c"));
        assert_eq!(shaped[1]["findingId"].as_str(), Some("b"));
        assert_eq!(shaped[2]["findingId"].as_str(), Some("a"));
    }
}
