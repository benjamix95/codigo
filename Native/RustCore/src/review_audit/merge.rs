use super::helpers::pack_payload;
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashSet};

pub(crate) fn merge_audit_results(
    tool_name: &str,
    summary_prefix: &str,
    results: Vec<Value>,
) -> Value {
    let mut findings: Vec<Value> = Vec::new();
    let mut adapters: Vec<String> = Vec::new();
    let mut coverage = false;
    for r in results {
        if let Some(arr) = r.get("findings").and_then(|x| x.as_array()) {
            findings.extend(arr.iter().cloned());
        }
        coverage |= r
            .get("coverageAvailable")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        if let Some(a) = r.get("adaptersUsed").and_then(|x| x.as_array()) {
            for v in a {
                if let Some(s) = v.as_str() {
                    if !adapters.iter().any(|x| x == s) {
                        adapters.push(s.to_string());
                    }
                }
            }
        }
    }
    dedupe_findings_by_id(&mut findings);
    let clusters = build_correlation_clusters(&findings);
    let summary = if findings.is_empty() {
        format!("{summary_prefix}: no findings.")
    } else {
        format!(
            "{summary_prefix}: {} finding(s), {} cluster(s).",
            findings.len(),
            clusters.len()
        )
    };
    let metadata = json!({
        "signal_type": "multi_signal",
        "verification_hint": "Conferma reachability e severità prima della promozione",
        "promotion_gate": "strict_verified",
        "behavioral_impact": if findings.iter().any(|f| f.get("blocking").and_then(|b| b.as_bool()) == Some(true)) { "high_risk" } else { "mixed" }
    });
    pack_payload(
        tool_name, findings, coverage, summary, metadata, adapters, clusters,
    )
}

fn dedupe_findings_by_id(findings: &mut Vec<Value>) {
    let mut seen = HashSet::new();
    findings.retain(|f| {
        let id = f
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        seen.insert(id)
    });
}

fn build_correlation_clusters(findings: &[Value]) -> Vec<Value> {
    let mut groups: BTreeMap<String, Vec<&Value>> = BTreeMap::new();
    for f in findings {
        let msg = f
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .split('.')
            .next()
            .unwrap_or("")
            .to_lowercase();
        let cat = f
            .get("category")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown");
        let key = format!("{cat}|{msg}");
        groups.entry(key).or_default().push(f);
    }
    groups
        .into_iter()
        .enumerate()
        .map(|(i, (title, items))| {
            let files: Vec<String> = items
                .iter()
                .filter_map(|v| v.get("filePath").and_then(|x| x.as_str()))
                .collect::<HashSet<_>>()
                .into_iter()
                .map(String::from)
                .collect();
            let ids: Vec<String> = items
                .iter()
                .filter_map(|v| v.get("id").and_then(|x| x.as_str()))
                .map(String::from)
                .collect();
            let conf_sum: f64 = items
                .iter()
                .filter_map(|v| v.get("confidence").and_then(|x| x.as_f64()))
                .sum();
            let conf_n = items
                .iter()
                .filter(|v| v.get("confidence").is_some())
                .count();
            let avg = if conf_n > 0 {
                conf_sum / conf_n as f64
            } else {
                0.0
            };
            json!({
                "id": format!("cluster-{}", i + 1),
                "title": title,
                "files": files,
                "findingIDs": ids,
                "confidence": avg
            })
        })
        .collect()
}
