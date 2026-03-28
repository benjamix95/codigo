//! Trending / baseline storica per performance audit findings.
//!
//! Saves audit results to a `.performance-audit-baseline.json` file
//! and computes deltas (new issues, resolved, regressions) on subsequent runs.

use super::helpers::pack_payload;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::PathBuf;

const BASELINE_FILE: &str = ".performance-audit-baseline.json";

/// A snapshot of findings for comparison.
#[derive(Debug, Clone)]
pub(crate) struct FindingSnapshot {
    pub id: String,
    pub file: String,
    pub line: u64,
    pub severity: String,
    pub message: String,
    pub tool: String,
}

/// Delta between baseline and current run.
#[derive(Debug, Clone)]
pub(crate) struct TrendingDelta {
    pub new_findings: Vec<FindingSnapshot>,
    pub resolved_findings: Vec<FindingSnapshot>,
    pub persistent_findings: Vec<FindingSnapshot>,
    pub regressions: Vec<FindingSnapshot>,
}

/// Load baseline from workspace.
pub(crate) fn load_baseline(workspace_path: &str) -> Option<Vec<FindingSnapshot>> {
    let path = PathBuf::from(workspace_path).join(BASELINE_FILE);
    let content = fs::read_to_string(&path).ok()?;
    let parsed: Value = serde_json::from_str(&content).ok()?;
    let arr = parsed.as_array()?;
    Some(
        arr.iter()
            .filter_map(|v| {
                Some(FindingSnapshot {
                    id: v.get("id")?.as_str()?.to_string(),
                    file: v.get("file")?.as_str()?.to_string(),
                    line: v.get("line")?.as_u64()?,
                    severity: v.get("severity")?.as_str()?.to_string(),
                    message: v.get("message")?.as_str()?.to_string(),
                    tool: v.get("tool")?.as_str()?.to_string(),
                })
            })
            .collect(),
    )
}

/// Save current findings as the new baseline.
pub(crate) fn save_baseline(
    workspace_path: &str,
    findings: &[FindingSnapshot],
) -> Result<(), String> {
    let path = PathBuf::from(workspace_path).join(BASELINE_FILE);
    let arr: Vec<Value> = findings
        .iter()
        .map(|f| {
            json!({
                "id": f.id,
                "file": f.file,
                "line": f.line,
                "severity": f.severity,
                "message": f.message,
                "tool": f.tool,
            })
        })
        .collect();
    let content = serde_json::to_string_pretty(&arr)
        .map_err(|e| format!("serialize baseline: {e}"))?;
    fs::write(&path, content).map_err(|e| format!("write baseline: {e}"))
}

/// Extract FindingSnapshots from a tool result JSON.
pub(crate) fn extract_snapshots(result: &Value) -> Vec<FindingSnapshot> {
    let tool = result
        .get("toolName")
        .and_then(|t| t.as_str())
        .unwrap_or("unknown");
    result
        .get("findings")
        .and_then(|f| f.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|f| {
                    Some(FindingSnapshot {
                        id: f.get("id")?.as_str()?.to_string(),
                        file: f.get("filePath")?.as_str()?.to_string(),
                        line: f.get("lineNumber")?.as_u64().unwrap_or(0),
                        severity: f.get("severity")?.as_str()?.to_string(),
                        message: f.get("message")?.as_str()?.to_string(),
                        tool: tool.to_string(),
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

/// Compute a stable fingerprint for a finding (file + message, ignoring line).
fn fingerprint(f: &FindingSnapshot) -> String {
    format!("{}::{}", f.file, f.message)
}

/// Compute the delta between baseline and current findings.
pub(crate) fn compute_delta(
    baseline: &[FindingSnapshot],
    current: &[FindingSnapshot],
) -> TrendingDelta {
    let baseline_fps: HashSet<String> = baseline.iter().map(fingerprint).collect();
    let current_fps: HashSet<String> = current.iter().map(fingerprint).collect();

    let baseline_map: HashMap<String, &FindingSnapshot> =
        baseline.iter().map(|f| (fingerprint(f), f)).collect();

    let mut new_findings = Vec::new();
    let mut persistent = Vec::new();
    let mut regressions = Vec::new();

    for f in current {
        let fp = fingerprint(f);
        if !baseline_fps.contains(&fp) {
            new_findings.push(f.clone());
        } else {
            persistent.push(f.clone());
            // Check for regression: severity got worse
            if let Some(base_f) = baseline_map.get(&fp) {
                if severity_rank(&f.severity) > severity_rank(&base_f.severity) {
                    regressions.push(f.clone());
                }
            }
        }
    }

    let resolved: Vec<FindingSnapshot> = baseline
        .iter()
        .filter(|f| !current_fps.contains(&fingerprint(f)))
        .cloned()
        .collect();

    TrendingDelta {
        new_findings,
        resolved_findings: resolved,
        persistent_findings: persistent,
        regressions,
    }
}

fn severity_rank(s: &str) -> u8 {
    match s {
        "critical" => 3,
        "warning" => 2,
        "suggestion" => 1,
        _ => 0,
    }
}

/// Run trending analysis: compare current results against baseline,
/// produce a delta report, and optionally update the baseline.
pub(crate) fn run_perf_trending(
    current_results: &[Value],
    workspace_path: &str,
    update_baseline: bool,
) -> Result<Value, String> {
    // Extract current snapshots from all results
    let current: Vec<FindingSnapshot> = current_results
        .iter()
        .flat_map(extract_snapshots)
        .collect();

    // Load baseline
    let baseline = load_baseline(workspace_path).unwrap_or_default();
    let has_baseline = !baseline.is_empty();

    // Compute delta
    let delta = compute_delta(&baseline, &current);

    // Optionally save new baseline
    if update_baseline {
        save_baseline(workspace_path, &current)?;
    }

    // Build findings for the delta report
    let mut findings: Vec<Value> = Vec::new();

    for f in &delta.new_findings {
        findings.push(json!({
            "id": format!("trending-new-{}", f.id),
            "severity": f.severity,
            "category": "performance_trending",
            "origin": "audit_tool",
            "filePath": f.file,
            "lineNumber": f.line,
            "message": format!("[NEW] {}", f.message),
            "suggestedFix": "New issue since last baseline — investigate.",
            "confidence": 0.80,
            "trendingStatus": "new",
            "sourceTool": "audit_perf_trending",
            "blocking": f.severity == "critical",
            "status": "open"
        }));
    }

    for f in &delta.regressions {
        findings.push(json!({
            "id": format!("trending-regressed-{}", f.id),
            "severity": "critical",
            "category": "performance_trending",
            "origin": "audit_tool",
            "filePath": f.file,
            "lineNumber": f.line,
            "message": format!("[REGRESSION] {}", f.message),
            "suggestedFix": "Severity increased since last baseline — prioritize fix.",
            "confidence": 0.90,
            "trendingStatus": "regressed",
            "sourceTool": "audit_perf_trending",
            "blocking": true,
            "status": "open"
        }));
    }

    for f in &delta.resolved_findings {
        findings.push(json!({
            "id": format!("trending-resolved-{}", f.id),
            "severity": "suggestion",
            "category": "performance_trending",
            "origin": "audit_tool",
            "filePath": f.file,
            "lineNumber": f.line,
            "message": format!("[RESOLVED] {}", f.message),
            "suggestedFix": "Previously flagged issue no longer present.",
            "confidence": 0.95,
            "trendingStatus": "resolved",
            "sourceTool": "audit_perf_trending",
            "blocking": false,
            "status": "resolved"
        }));
    }

    let summary = format!(
        "audit_perf_trending: {} new, {} resolved, {} persistent, {} regression(s). Baseline: {}.",
        delta.new_findings.len(),
        delta.resolved_findings.len(),
        delta.persistent_findings.len(),
        delta.regressions.len(),
        if has_baseline { "loaded" } else { "none (first run)" }
    );

    Ok(pack_payload(
        "audit_perf_trending",
        findings,
        true,
        summary,
        json!({
            "signal_type": "trending",
            "has_baseline": has_baseline,
            "baseline_updated": update_baseline,
            "new_count": delta.new_findings.len(),
            "resolved_count": delta.resolved_findings.len(),
            "persistent_count": delta.persistent_findings.len(),
            "regression_count": delta.regressions.len(),
        }),
        vec![],
        vec![],
    ))
}

// Tests moved to tests_perf_trending.rs for file size compliance.
