//! Configurable performance audit thresholds via `.performance-audit.yml`.
//!
//! Loads project-specific configuration from the workspace root.
//! Falls back to sensible defaults if the file is absent or malformed.

use super::perf_churn::ChurnThresholds;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

/// Full configuration for performance audit tools.
#[derive(Debug, Clone)]
pub(crate) struct PerfAuditConfig {
    /// Severity overrides per pattern needle (lowercase).
    /// Key: pattern needle, Value: severity string.
    pub severity_overrides: HashMap<String, String>,

    /// Patterns to ignore (lowercase needles). Findings matching these are skipped.
    pub ignore_patterns: Vec<String>,

    /// File path patterns to exclude from analysis.
    pub exclude_paths: Vec<String>,

    /// Minimum confidence threshold. Findings below this are filtered out.
    pub min_confidence: f64,

    /// Churn thresholds for severity weighting.
    pub churn: ChurnThresholds,

    /// Whether churn-weighted scoring is enabled.
    pub churn_enabled: bool,

    /// Whether to include test/mock files in the analysis.
    pub include_test_files: bool,

    /// Maximum findings per file (0 = unlimited).
    pub max_findings_per_file: usize,
}

impl Default for PerfAuditConfig {
    fn default() -> Self {
        Self {
            severity_overrides: HashMap::new(),
            ignore_patterns: Vec::new(),
            exclude_paths: Vec::new(),
            min_confidence: 0.0,
            churn: ChurnThresholds::default(),
            churn_enabled: true,
            include_test_files: true,
            max_findings_per_file: 0,
        }
    }
}

/// Load performance audit configuration from workspace.
///
/// Looks for `.performance-audit.yml` in the workspace root.
/// Parses a simple key-value YAML subset (no full YAML parser dependency).
pub(crate) fn load_perf_config(workspace_path: &str) -> PerfAuditConfig {
    let config_path = PathBuf::from(workspace_path).join(".performance-audit.yml");
    let content = match fs::read_to_string(&config_path) {
        Ok(c) => c,
        Err(_) => return PerfAuditConfig::default(),
    };
    parse_perf_config(&content)
}

/// Parse configuration from YAML-like content.
///
/// Supports a simple subset:
/// ```yaml
/// min_confidence: 0.5
/// churn_enabled: true
/// churn_high_commits: 20
/// churn_low_commits: 5
/// churn_lookback_days: 60
/// include_test_files: false
/// max_findings_per_file: 10
/// ignore_patterns:
///   - "todo:"
///   - ".clone()"
/// exclude_paths:
///   - "vendor/"
///   - "generated/"
/// severity_overrides:
///   "thread.sleep": "critical"
/// ```
fn parse_perf_config(content: &str) -> PerfAuditConfig {
    let mut config = PerfAuditConfig::default();
    let mut current_section: Option<&str> = None;

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }

        // Detect list items under a section
        if trimmed.starts_with("- ") {
            let value = trimmed[2..].trim().trim_matches('"').to_string();
            match current_section {
                Some("ignore_patterns") => config.ignore_patterns.push(value.to_lowercase()),
                Some("exclude_paths") => config.exclude_paths.push(value),
                _ => {}
            }
            continue;
        }

        // Detect key-value pairs with ": " inside a section
        if let Some(section) = current_section {
            if section == "severity_overrides" {
                if let Some((key, val)) = trimmed.split_once(':') {
                    let k = key.trim().trim_matches('"').to_lowercase();
                    let v = val.trim().trim_matches('"').to_string();
                    if !k.is_empty() && !v.is_empty() {
                        config.severity_overrides.insert(k, v);
                        continue;
                    }
                }
            }
        }

        // Top-level key: value
        if let Some((key, value)) = trimmed.split_once(':') {
            let k = key.trim();
            let v = value.trim();

            // Section headers (value is empty or just whitespace)
            if v.is_empty() {
                current_section = match k {
                    "ignore_patterns" => Some("ignore_patterns"),
                    "exclude_paths" => Some("exclude_paths"),
                    "severity_overrides" => Some("severity_overrides"),
                    _ => None,
                };
                continue;
            }

            current_section = None;
            match k {
                "min_confidence" => {
                    config.min_confidence = v.parse().unwrap_or(0.0);
                }
                "churn_enabled" => {
                    config.churn_enabled = v == "true";
                }
                "churn_high_commits" => {
                    config.churn.high_churn_commits = v.parse().unwrap_or(15);
                }
                "churn_low_commits" => {
                    config.churn.low_churn_commits = v.parse().unwrap_or(3);
                }
                "churn_lookback_days" => {
                    config.churn.lookback_days = v.parse().unwrap_or(90);
                }
                "include_test_files" => {
                    config.include_test_files = v == "true";
                }
                "max_findings_per_file" => {
                    config.max_findings_per_file = v.parse().unwrap_or(0);
                }
                _ => {}
            }
        }
    }

    config
}

/// Check if a file path matches any exclude pattern.
pub(crate) fn is_excluded_path(file: &str, exclude_paths: &[String]) -> bool {
    let lower = file.to_lowercase();
    exclude_paths.iter().any(|pat| lower.contains(&pat.to_lowercase()))
}

/// Check if a pattern needle is in the ignore list.
pub(crate) fn is_ignored_pattern(needle: &str, ignore_patterns: &[String]) -> bool {
    let lower = needle.to_lowercase();
    ignore_patterns.iter().any(|pat| lower.contains(pat))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_empty_returns_defaults() {
        let config = parse_perf_config("");
        assert_eq!(config.min_confidence, 0.0);
        assert!(config.churn_enabled);
        assert!(config.include_test_files);
        assert_eq!(config.max_findings_per_file, 0);
    }

    #[test]
    fn parse_basic_config() {
        let yaml = r#"
min_confidence: 0.5
churn_enabled: false
churn_high_commits: 20
churn_lookback_days: 60
include_test_files: false
max_findings_per_file: 10
ignore_patterns:
  - "todo:"
  - ".clone()"
exclude_paths:
  - "vendor/"
  - "generated/"
"#;
        let config = parse_perf_config(yaml);
        assert!((config.min_confidence - 0.5).abs() < 0.01);
        assert!(!config.churn_enabled);
        assert_eq!(config.churn.high_churn_commits, 20);
        assert_eq!(config.churn.lookback_days, 60);
        assert!(!config.include_test_files);
        assert_eq!(config.max_findings_per_file, 10);
        assert_eq!(config.ignore_patterns, vec!["todo:", ".clone()"]);
        assert_eq!(config.exclude_paths, vec!["vendor/", "generated/"]);
    }

    #[test]
    fn parse_severity_overrides() {
        let yaml = r#"
severity_overrides:
  "thread.sleep": "critical"
  ".clone()": "warning"
"#;
        let config = parse_perf_config(yaml);
        assert_eq!(config.severity_overrides.get("thread.sleep").map(|s| s.as_str()), Some("critical"));
        assert_eq!(config.severity_overrides.get(".clone()").map(|s| s.as_str()), Some("warning"));
    }

    #[test]
    fn is_excluded_path_matches() {
        let excludes = vec!["vendor/".to_string(), "generated/".to_string()];
        assert!(is_excluded_path("vendor/lib/foo.rs", &excludes));
        assert!(is_excluded_path("src/generated/models.rs", &excludes));
        assert!(!is_excluded_path("src/main.rs", &excludes));
    }

    #[test]
    fn is_ignored_pattern_matches() {
        let ignores = vec!["todo:".to_string(), ".clone()".to_string()];
        assert!(is_ignored_pattern("TODO:", &ignores));
        assert!(is_ignored_pattern(".clone()", &ignores));
        assert!(!is_ignored_pattern("thread.sleep", &ignores));
    }
}
