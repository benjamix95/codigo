use crate::review_projection::build_projection;
use serde_json::{json, Value};

pub fn build_replay_report(envelope: &Value, checkpoint_source: &str) -> Result<Value, String> {
    let canonical = envelope
        .get("canonicalSnapshot")
        .ok_or_else(|| "missing canonicalSnapshot".to_string())?;
    let findings = canonical
        .get("findings")
        .and_then(Value::as_object)
        .map(|items| items.values().cloned().collect::<Vec<_>>())
        .unwrap_or_default();
    let trace_log = canonical
        .get("traceLog")
        .and_then(Value::as_array)
        .map(|items| {
            items.iter()
                .filter_map(Value::as_str)
                .map(ToString::to_string)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let projection = build_projection(&findings, &trace_log);
    let event_count = canonical
        .get("eventLog")
        .and_then(Value::as_array)
        .map_or(0, |items| items.len());

    Ok(json!({
        "sessionId": envelope.get("sessionId").and_then(Value::as_str).unwrap_or_default(),
        "checkpointSource": checkpoint_source,
        "eventSchemaVersion": envelope.get("eventSchemaVersion").and_then(Value::as_i64).unwrap_or(1),
        "projectionSchemaVersion": envelope.get("projectionSchemaVersion").and_then(Value::as_i64).unwrap_or(1),
        "entitySchemaVersion": envelope.get("entitySchemaVersion").and_then(Value::as_i64).unwrap_or(1),
        "findingCount": findings.len(),
        "eventCount": event_count,
        "traceCount": trace_log.len(),
        "candidateCount": projection["candidateQueue"].as_array().map_or(0, |items| items.len()),
        "verifiedCount": projection["verifiedQueue"].as_array().map_or(0, |items| items.len()),
        "duplicatesCount": projection["duplicatesCount"].as_i64().unwrap_or(0),
        "staleCandidatesCount": projection["staleCandidatesCount"].as_i64().unwrap_or(0)
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn builds_replay_report_from_envelope() {
        let envelope = json!({
            "sessionId":"session-1",
            "eventSchemaVersion":1,
            "projectionSchemaVersion":1,
            "entitySchemaVersion":1,
            "canonicalSnapshot":{
                "findings":{
                    "a":{"id":"a","title":"A","domain":"bug","status":"candidate","staleStatus":"active","severity":"medium","filePath":"A.swift","possibleDuplicateOf":[]},
                    "b":{"id":"b","title":"B","domain":"bug","status":"verified","staleStatus":"active","severity":"high","filePath":"B.swift","possibleDuplicateOf":[]}
                },
                "eventLog":[{},{}],
                "traceLog":["x","y"]
            }
        });
        let report = build_replay_report(&envelope, "storedEnvelope").unwrap();
        assert_eq!(report["findingCount"].as_i64(), Some(2));
        assert_eq!(report["candidateCount"].as_i64(), Some(1));
        assert_eq!(report["verifiedCount"].as_i64(), Some(1));
    }
}
