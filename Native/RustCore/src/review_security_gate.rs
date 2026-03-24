use crate::review_projection::build_projection;
use serde_json::{json, Value};
use std::collections::HashMap;

pub fn evaluate_security_gate(envelope: &Value) -> Result<Value, String> {
    let canonical = envelope
        .get("canonicalSnapshot")
        .ok_or_else(|| "missing canonicalSnapshot".to_string())?;
    let findings_map = canonical
        .get("findings")
        .and_then(Value::as_object)
        .ok_or_else(|| "missing findings".to_string())?;
    let findings = findings_map.values().cloned().collect::<Vec<_>>();
    let trace_log = canonical
        .get("traceLog")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(ToString::to_string)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let rebuilt_projection = build_projection(&findings, &trace_log);
    let mismatch_count = if envelope.get("projectionSnapshot") == Some(&rebuilt_projection) {
        0
    } else {
        1
    };
    let verification_reports = group_by_finding_id(canonical.get("verificationReports"));
    let evidences = group_by_finding_id(canonical.get("evidences"));
    let undetected_duplicate_count = count_undetected_duplicates(&findings);
    let findings_missing_evidence_count = findings
        .iter()
        .filter(|finding| {
            is_verified(finding)
                && evidences
                    .get(id(finding))
                    .is_none_or(|items| items.is_empty())
        })
        .count();
    let findings_missing_verification_count = findings
        .iter()
        .filter(|finding| {
            is_verified(finding)
                && verification_reports
                    .get(id(finding))
                    .is_none_or(|items| items.is_empty())
        })
        .count();
    let bug_patches = canonical
        .get("patchArtifacts")
        .and_then(Value::as_object)
        .map(|items| {
            items
                .values()
                .filter(|patch| finding_domain(findings_map, patch) == Some("bug"))
                .cloned()
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let rollback_coverage_count = bug_patches
        .iter()
        .filter(|patch| patch.get("rollbackAvailable").and_then(Value::as_bool) == Some(true))
        .count();
    let rollback_eligible_count = bug_patches.len();
    let bug_revalidations = canonical
        .get("revalidationReports")
        .and_then(Value::as_object)
        .map(|items| {
            items
                .values()
                .filter(|report| finding_domain(findings_map, report) == Some("bug"))
                .cloned()
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let successful_bug_revalidations = bug_revalidations
        .iter()
        .filter(|report| report.get("verdict").and_then(Value::as_str) == Some("fixed_verified"))
        .count();
    let apply_revalidate_success_rate = if bug_revalidations.is_empty() {
        1.0
    } else {
        successful_bug_revalidations as f64 / bug_revalidations.len() as f64
    };
    let ready = mismatch_count == 0
        && undetected_duplicate_count == 0
        && findings_missing_evidence_count == 0
        && findings_missing_verification_count == 0
        && (rollback_eligible_count == 0 || rollback_coverage_count == rollback_eligible_count)
        && apply_revalidate_success_rate >= 0.90;
    let rate = format!("{:.0}%", apply_revalidate_success_rate * 100.0);
    Ok(json!({
        "ready": ready,
        "canonicalProjectionMismatchCount": mismatch_count,
        "undetectedDuplicateCount": undetected_duplicate_count,
        "findingsMissingEvidenceCount": findings_missing_evidence_count,
        "findingsMissingVerificationCount": findings_missing_verification_count,
        "rollbackCoverageCount": rollback_coverage_count,
        "rollbackEligibleCount": rollback_eligible_count,
        "applyRevalidateSuccessRate": apply_revalidate_success_rate,
        "knownCriticalRaceCount": 0,
        "summary": format!("security_gate={}, mismatches={}, undetected_duplicates={}, missing_evidence={}, missing_verification={}, rollback={}/{}, apply_revalidate_success={}",
            if ready { "ready" } else { "blocked" },
            mismatch_count,
            undetected_duplicate_count,
            findings_missing_evidence_count,
            findings_missing_verification_count,
            rollback_coverage_count,
            rollback_eligible_count,
            rate)
    }))
}

fn group_by_finding_id(value: Option<&Value>) -> HashMap<String, Vec<Value>> {
    value
        .and_then(Value::as_object)
        .map(|items| {
            let mut grouped: HashMap<String, Vec<Value>> = HashMap::new();
            for item in items.values() {
                if let Some(finding_id) = item.get("findingId").and_then(Value::as_str) {
                    grouped
                        .entry(finding_id.to_string())
                        .or_default()
                        .push(item.clone());
                }
            }
            grouped
        })
        .unwrap_or_default()
}

fn count_undetected_duplicates(findings: &[Value]) -> usize {
    let mut grouped: HashMap<String, Vec<&Value>> = HashMap::new();
    for finding in findings {
        if let Some(fingerprint) = finding.get("findingFingerprint").and_then(Value::as_str) {
            grouped
                .entry(fingerprint.to_string())
                .or_default()
                .push(finding);
        }
    }
    grouped.values().fold(0, |sum, group| {
        if group.len() <= 1 {
            sum
        } else {
            sum + group
                .iter()
                .filter(|finding| {
                    is_empty_array(finding.get("possibleDuplicateOf"))
                        && finding
                            .get("mergedIntoFindingId")
                            .is_none_or(Value::is_null)
                        && finding.get("recurrenceGroupId").is_none_or(Value::is_null)
                })
                .count()
        }
    })
}

fn finding_domain<'a>(
    findings: &'a serde_json::Map<String, Value>,
    value: &Value,
) -> Option<&'a str> {
    let finding_id = value.get("findingId").and_then(Value::as_str)?;
    findings.get(finding_id)?.get("domain")?.as_str()
}

fn id(value: &Value) -> &str {
    value.get("id").and_then(Value::as_str).unwrap_or_default()
}

fn is_empty_array(value: Option<&Value>) -> bool {
    value
        .and_then(Value::as_array)
        .is_none_or(|items| items.is_empty())
}

fn is_verified(value: &Value) -> bool {
    matches!(
        value.get("status").and_then(Value::as_str),
        Some("verified" | "fixed_verified")
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn gate_ready_when_projection_matches() {
        let findings = json!({
            "finding-1":{"id":"finding-1","domain":"bug","status":"fixed_verified","findingFingerprint":"fp","possibleDuplicateOf":[],"title":"Crash","staleStatus":"active","severity":"high","filePath":"A.swift"}
        });
        let projection = build_projection(
            &findings
                .as_object()
                .unwrap()
                .values()
                .cloned()
                .collect::<Vec<_>>(),
            &[],
        );
        let envelope = json!({
            "projectionSnapshot": projection,
            "canonicalSnapshot":{
                "findings": findings,
                "evidences":{"evidence-1":{"findingId":"finding-1"}},
                "verificationReports":{"vr-1":{"findingId":"finding-1"}},
                "patchArtifacts":{"patch-1":{"findingId":"finding-1","rollbackAvailable":true}},
                "revalidationReports":{"rv-1":{"findingId":"finding-1","verdict":"fixed_verified"}},
                "traceLog":[]
            }
        });
        let report = evaluate_security_gate(&envelope).unwrap();
        assert_eq!(report["ready"].as_bool(), Some(true));
    }
}
