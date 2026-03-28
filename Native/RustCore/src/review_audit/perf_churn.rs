//! Git churn integration for performance audit severity weighting.
//!
//! Files modified frequently (high churn) get boosted severity because
//! performance issues in hot-churn files have higher blast radius.

use serde_json::{json, Value};
use std::collections::HashMap;
use std::process::Command;

/// Churn data for a single file.
#[derive(Debug, Clone)]
pub(crate) struct FileChurnInfo {
    pub commit_count: u32,
    pub days_since_last_change: u32,
}

/// Thresholds for churn-based severity adjustment.
#[derive(Debug, Clone)]
pub(crate) struct ChurnThresholds {
    /// Commits in the lookback window above which a file is "high churn".
    pub high_churn_commits: u32,
    /// Commits below which a file is "low churn" (no boost).
    pub low_churn_commits: u32,
    /// Days of git history to analyze.
    pub lookback_days: u32,
}

impl Default for ChurnThresholds {
    fn default() -> Self {
        Self {
            high_churn_commits: 15,
            low_churn_commits: 3,
            lookback_days: 90,
        }
    }
}

/// Collect git churn data for the given files within a workspace.
///
/// Runs `git log --name-only` and counts per-file commit frequency.
/// Returns empty map if git is unavailable or the workspace is not a repo.
pub(crate) fn collect_churn_data(
    workspace_path: &str,
    scope_files: &[String],
    thresholds: &ChurnThresholds,
) -> HashMap<String, FileChurnInfo> {
    let mut result = HashMap::new();

    let output = Command::new("git")
        .args([
            "log",
            "--name-only",
            "--format=",
            &format!("--since={} days ago", thresholds.lookback_days),
        ])
        .current_dir(workspace_path)
        .output();

    let output = match output {
        Ok(o) if o.status.success() => o,
        _ => return result,
    };

    let stdout = String::from_utf8_lossy(&output.stdout);

    // Count commits per file
    let mut counts: HashMap<String, u32> = HashMap::new();
    for line in stdout.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        *counts.entry(trimmed.to_string()).or_insert(0) += 1;
    }

    // Only include files in scope
    let scope_set: std::collections::HashSet<&str> =
        scope_files.iter().map(|s| s.as_str()).collect();

    for (file, count) in counts {
        if scope_set.contains(file.as_str()) {
            result.insert(
                file,
                FileChurnInfo {
                    commit_count: count,
                    days_since_last_change: 0, // simplified — could parse dates
                },
            );
        }
    }

    result
}

/// Classify churn level for a file.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ChurnLevel {
    High,
    Medium,
    Low,
}

pub(crate) fn classify_churn(
    info: Option<&FileChurnInfo>,
    thresholds: &ChurnThresholds,
) -> ChurnLevel {
    match info {
        Some(i) if i.commit_count >= thresholds.high_churn_commits => ChurnLevel::High,
        Some(i) if i.commit_count > thresholds.low_churn_commits => ChurnLevel::Medium,
        _ => ChurnLevel::Low,
    }
}

/// Apply churn-based severity boost to a finding's severity and confidence.
///
/// - High churn: suggestion → warning, confidence +0.10
/// - Medium churn: confidence +0.05
/// - Low churn: no change
pub(crate) fn apply_churn_boost(
    severity: &str,
    confidence: f64,
    churn_level: ChurnLevel,
) -> (&'static str, f64) {
    match churn_level {
        ChurnLevel::High => {
            let boosted_sev = match severity {
                "suggestion" => "warning",
                other => leak_str(other),
            };
            (boosted_sev, (confidence + 0.10).min(0.99))
        }
        ChurnLevel::Medium => {
            (leak_str(severity), (confidence + 0.05).min(0.99))
        }
        ChurnLevel::Low => (leak_str(severity), confidence),
    }
}

/// Convert a &str to &'static str by leaking.
/// Only used for a small fixed set of severity strings.
fn leak_str(s: &str) -> &'static str {
    match s {
        "critical" => "critical",
        "warning" => "warning",
        "suggestion" => "suggestion",
        _ => "suggestion",
    }
}

/// Enrich a finding JSON value with churn metadata.
pub(crate) fn enrich_finding_with_churn(
    finding: &mut Value,
    churn_info: Option<&FileChurnInfo>,
    churn_level: ChurnLevel,
) {
    if let Some(info) = churn_info {
        finding["churnCommitCount"] = json!(info.commit_count);
        finding["churnLevel"] = json!(format!("{:?}", churn_level));
    } else {
        finding["churnCommitCount"] = json!(0);
        finding["churnLevel"] = json!("Unknown");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classify_churn_levels() {
        let thresholds = ChurnThresholds::default();

        let high = FileChurnInfo { commit_count: 20, days_since_last_change: 1 };
        assert_eq!(classify_churn(Some(&high), &thresholds), ChurnLevel::High);

        let medium = FileChurnInfo { commit_count: 8, days_since_last_change: 5 };
        assert_eq!(classify_churn(Some(&medium), &thresholds), ChurnLevel::Medium);

        let low = FileChurnInfo { commit_count: 2, days_since_last_change: 30 };
        assert_eq!(classify_churn(Some(&low), &thresholds), ChurnLevel::Low);

        assert_eq!(classify_churn(None, &thresholds), ChurnLevel::Low);
    }

    #[test]
    fn churn_boost_upgrades_severity() {
        let (sev, conf) = apply_churn_boost("suggestion", 0.50, ChurnLevel::High);
        assert_eq!(sev, "warning");
        assert!((conf - 0.60).abs() < 0.01);

        let (sev, conf) = apply_churn_boost("warning", 0.80, ChurnLevel::Medium);
        assert_eq!(sev, "warning");
        assert!((conf - 0.85).abs() < 0.01);

        let (sev, conf) = apply_churn_boost("warning", 0.80, ChurnLevel::Low);
        assert_eq!(sev, "warning");
        assert!((conf - 0.80).abs() < 0.01);
    }

    #[test]
    fn enrich_finding_adds_churn_fields() {
        let mut finding = json!({"message": "test"});
        let info = FileChurnInfo { commit_count: 25, days_since_last_change: 2 };
        enrich_finding_with_churn(&mut finding, Some(&info), ChurnLevel::High);
        assert_eq!(finding["churnCommitCount"].as_u64(), Some(25));
        assert_eq!(finding["churnLevel"].as_str(), Some("High"));
    }
}
