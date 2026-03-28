//! Tests for perf_trending module — baseline, delta, regression tracking.

use super::perf_trending::*;
use serde_json::json;

#[test]
fn compute_delta_new_and_resolved() {
    let baseline = vec![FindingSnapshot {
        id: "old-1".into(),
        file: "a.swift".into(),
        line: 10,
        severity: "warning".into(),
        message: "Thread.sleep".into(),
        tool: "bottlenecks".into(),
    }];
    let current = vec![FindingSnapshot {
        id: "new-1".into(),
        file: "b.rs".into(),
        line: 5,
        severity: "warning".into(),
        message: "clone()".into(),
        tool: "bottlenecks".into(),
    }];
    let delta = compute_delta(&baseline, &current);
    assert_eq!(delta.new_findings.len(), 1);
    assert_eq!(delta.resolved_findings.len(), 1);
    assert_eq!(delta.persistent_findings.len(), 0);
    assert_eq!(delta.regressions.len(), 0);
}

#[test]
fn compute_delta_regression_detected() {
    let baseline = vec![FindingSnapshot {
        id: "f1".into(),
        file: "a.swift".into(),
        line: 10,
        severity: "suggestion".into(),
        message: "slow call".into(),
        tool: "bottlenecks".into(),
    }];
    let current = vec![FindingSnapshot {
        id: "f1".into(),
        file: "a.swift".into(),
        line: 10,
        severity: "critical".into(),
        message: "slow call".into(),
        tool: "bottlenecks".into(),
    }];
    let delta = compute_delta(&baseline, &current);
    assert_eq!(delta.regressions.len(), 1);
    assert_eq!(delta.persistent_findings.len(), 1);
    assert_eq!(delta.new_findings.len(), 0);
}

#[test]
fn extract_snapshots_from_result() {
    let result = json!({
        "toolName": "audit_perf_bottlenecks",
        "findings": [{
            "id": "f1",
            "filePath": "src/main.rs",
            "lineNumber": 42,
            "severity": "warning",
            "message": "thread::sleep detected"
        }]
    });
    let snaps = extract_snapshots(&result);
    assert_eq!(snaps.len(), 1);
    assert_eq!(snaps[0].tool, "audit_perf_bottlenecks");
    assert_eq!(snaps[0].line, 42);
}

#[test]
fn save_and_load_baseline_roundtrip() {
    let root = std::env::temp_dir().join(format!(
        "perf-trending-test-{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&root).unwrap();

    let findings = vec![FindingSnapshot {
        id: "f1".into(),
        file: "main.rs".into(),
        line: 10,
        severity: "warning".into(),
        message: "test".into(),
        tool: "tool".into(),
    }];

    save_baseline(root.to_str().unwrap(), &findings).unwrap();
    let loaded = load_baseline(root.to_str().unwrap()).unwrap();
    assert_eq!(loaded.len(), 1);
    assert_eq!(loaded[0].id, "f1");
}
