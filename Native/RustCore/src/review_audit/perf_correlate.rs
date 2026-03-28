//! Cross-tool correlation for performance audit findings.
//!
//! Correlates performance findings with bug/concurrency/error findings
//! to identify compound issues (e.g., a bottleneck that also has a race condition).

use super::dispatch::dispatch_standard_audit;
use super::helpers::pack_payload;
use serde_json::{json, Value};
use std::collections::HashMap;

/// A correlated cluster of findings affecting the same file.
#[derive(Debug, Clone)]
struct CorrelationCluster {
    file: String,
    perf_findings: Vec<Value>,
    bug_findings: Vec<Value>,
    compound_severity: &'static str,
    correlation_score: f64,
}

/// Tools to correlate with performance findings.
const CORRELATION_TOOLS: &[&str] = &[
    "audit_bug_concurrency",
    "audit_bug_error_handling",
    "audit_bug_state_machine",
    "audit_bug_nil_crash_paths",
];

/// Performance tools to gather findings from.
const PERF_TOOLS: &[&str] = &[
    "audit_perf_bottlenecks",
    "audit_perf_memory",
    "audit_perf_ui_responsiveness",
    "audit_perf_startup",
    "audit_perf_hot_paths",
];

/// Run cross-tool correlation: gather perf + bug findings, group by file,
/// identify compound issues.
pub(crate) fn run_perf_correlate(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    // Gather performance findings
    let mut perf_findings_by_file: HashMap<String, Vec<Value>> = HashMap::new();
    for tool in PERF_TOOLS {
        if let Ok(result) = dispatch_standard_audit(tool, scope_files.clone(), workspace_path) {
            extract_findings_by_file(&result, &mut perf_findings_by_file);
        }
    }

    // Gather bug/concurrency findings
    let mut bug_findings_by_file: HashMap<String, Vec<Value>> = HashMap::new();
    for tool in CORRELATION_TOOLS {
        if let Ok(result) = dispatch_standard_audit(tool, scope_files.clone(), workspace_path) {
            extract_findings_by_file(&result, &mut bug_findings_by_file);
        }
    }

    // Build correlation clusters
    let mut clusters: Vec<CorrelationCluster> = Vec::new();
    let all_files: std::collections::HashSet<&String> = perf_findings_by_file
        .keys()
        .chain(bug_findings_by_file.keys())
        .collect();

    for file in all_files {
        let perf = perf_findings_by_file.get(file.as_str()).cloned().unwrap_or_default();
        let bugs = bug_findings_by_file.get(file.as_str()).cloned().unwrap_or_default();

        if perf.is_empty() && bugs.is_empty() {
            continue;
        }

        let has_both = !perf.is_empty() && !bugs.is_empty();
        let correlation_score = compute_correlation_score(&perf, &bugs);
        let compound_severity = if has_both && correlation_score > 0.7 {
            "critical"
        } else if has_both {
            "warning"
        } else if !perf.is_empty() {
            max_severity(&perf)
        } else {
            max_severity(&bugs)
        };

        clusters.push(CorrelationCluster {
            file: file.to_string(),
            perf_findings: perf,
            bug_findings: bugs,
            compound_severity,
            correlation_score,
        });
    }

    // Sort by correlation score descending
    clusters.sort_by(|a, b| b.correlation_score.partial_cmp(&a.correlation_score).unwrap());

    // Build output findings
    let findings: Vec<Value> = clusters
        .iter()
        .filter(|c| !c.perf_findings.is_empty() || !c.bug_findings.is_empty())
        .map(|c| {
            json!({
                "id": format!("perf_correlate-{}", c.file),
                "severity": c.compound_severity,
                "category": "performance_correlation",
                "origin": "audit_tool",
                "filePath": c.file,
                "message": format!(
                    "Correlated: {} perf + {} bug finding(s) in {}",
                    c.perf_findings.len(),
                    c.bug_findings.len(),
                    c.file
                ),
                "suggestedFix": if c.perf_findings.len() > 0 && c.bug_findings.len() > 0 {
                    "Address both performance and correctness issues together — they may be related."
                } else {
                    "Review the individual findings."
                },
                "confidence": c.correlation_score,
                "correlationScore": c.correlation_score,
                "perfFindingCount": c.perf_findings.len(),
                "bugFindingCount": c.bug_findings.len(),
                "hasCompoundIssue": !c.perf_findings.is_empty() && !c.bug_findings.is_empty(),
                "sourceTool": "audit_perf_correlate",
                "blocking": c.compound_severity == "critical",
                "status": "open"
            })
        })
        .collect();

    let summary = if findings.is_empty() {
        "audit_perf_correlate: nessuna correlazione rilevata.".to_string()
    } else {
        let compound = findings.iter().filter(|f| {
            f["hasCompoundIssue"].as_bool() == Some(true)
        }).count();
        format!(
            "audit_perf_correlate: {} cluster(s), {} compound issue(s).",
            findings.len(),
            compound
        )
    };

    Ok(pack_payload(
        "audit_perf_correlate",
        findings,
        true,
        summary,
        json!({
            "signal_type": "correlation",
            "perf_tools_used": PERF_TOOLS,
            "bug_tools_used": CORRELATION_TOOLS,
        }),
        vec![],
        vec![],
    ))
}

fn extract_findings_by_file(result: &Value, map: &mut HashMap<String, Vec<Value>>) {
    if let Some(findings) = result.get("findings").and_then(|f| f.as_array()) {
        for f in findings {
            if let Some(path) = f.get("filePath").and_then(|p| p.as_str()) {
                map.entry(path.to_string()).or_default().push(f.clone());
            }
        }
    }
}

fn compute_correlation_score(perf: &[Value], bugs: &[Value]) -> f64 {
    if perf.is_empty() && bugs.is_empty() {
        return 0.0;
    }
    if perf.is_empty() || bugs.is_empty() {
        let findings = if perf.is_empty() { bugs } else { perf };
        return avg_confidence(findings) * 0.5;
    }
    // Both present: compound score
    let perf_conf = avg_confidence(perf);
    let bug_conf = avg_confidence(bugs);
    let base = (perf_conf + bug_conf) / 2.0;
    // Boost for having both types
    (base * 1.3).min(0.99)
}

fn avg_confidence(findings: &[Value]) -> f64 {
    if findings.is_empty() {
        return 0.0;
    }
    let sum: f64 = findings
        .iter()
        .filter_map(|f| f.get("confidence").and_then(|c| c.as_f64()))
        .sum();
    sum / findings.len() as f64
}

fn max_severity(findings: &[Value]) -> &'static str {
    for f in findings {
        if f.get("severity").and_then(|s| s.as_str()) == Some("critical") {
            return "critical";
        }
    }
    for f in findings {
        if f.get("severity").and_then(|s| s.as_str()) == Some("warning") {
            return "warning";
        }
    }
    "suggestion"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn correlation_score_both_present() {
        let perf = vec![json!({"confidence": 0.80})];
        let bugs = vec![json!({"confidence": 0.70})];
        let score = compute_correlation_score(&perf, &bugs);
        assert!(score > 0.7);
        assert!(score <= 0.99);
    }

    #[test]
    fn correlation_score_only_perf() {
        let perf = vec![json!({"confidence": 0.80})];
        let bugs: Vec<Value> = vec![];
        let score = compute_correlation_score(&perf, &bugs);
        assert!(score > 0.0);
        assert!(score < 0.5);
    }

    #[test]
    fn correlation_score_empty() {
        let score = compute_correlation_score(&[], &[]);
        assert_eq!(score, 0.0);
    }

    #[test]
    fn max_severity_picks_highest() {
        let findings = vec![
            json!({"severity": "suggestion"}),
            json!({"severity": "critical"}),
            json!({"severity": "warning"}),
        ];
        assert_eq!(max_severity(&findings), "critical");
    }
}
