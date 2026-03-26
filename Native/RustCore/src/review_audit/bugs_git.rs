use super::helpers::{make_finding, make_result_standard};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;

pub(crate) fn run_bug_hotspots(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let history = git_history_file_counts(workspace_path);
    if history.is_empty() {
        return Ok(make_result_standard(
            "audit_bug_hotspots",
            vec![],
            false,
            "Git history unavailable for bug hotspot audit.",
            "Hotspot.",
            json!({"signal_type":"pattern","promotion_gate":"strict_verified"}),
        ));
    }
    let mut findings = Vec::new();
    for file in &scope_files {
        if let Some(&count) = history.get(file) {
            if count >= 3 {
                let (sev, conf) = if count >= 6 {
                    ("warning", 0.78_f64)
                } else {
                    ("suggestion", 0.62_f64)
                };
                findings.push(make_finding(
                    sev,
                    "regression",
                    "bugHunter",
                    file,
                    None,
                    "File changed frequently in the last 90 days and is a regression hotspot.",
                    "Review recent history carefully, add focused regression tests, and keep the patch narrow.",
                    Some(conf),
                    Some(&format!("git log count over 90 days: {count}")),
                    false,
                    Some("audit_bug_hotspots".to_string()),
                ));
            }
        }
    }
    Ok(make_result_standard(
        "audit_bug_hotspots",
        findings,
        true,
        "No recent regression hotspots detected in scoped files.",
        "Detected hotspot file(s) based on recent git history.",
        json!({"signal_type":"pattern","promotion_gate":"strict_verified"}),
    ))
}

fn git_history_file_counts(workspace_path: &str) -> HashMap<String, u32> {
    let Ok(output) = Command::new("/usr/bin/git")
        .args([
            "log",
            "--since=90.days.ago",
            "--name-only",
            "--pretty=format:",
        ])
        .current_dir(workspace_path)
        .output()
    else {
        return HashMap::new();
    };
    if !output.status.success() {
        return HashMap::new();
    }
    let text = String::from_utf8_lossy(&output.stdout);
    let mut counts: HashMap<String, u32> = HashMap::new();
    for line in text.lines() {
        let trimmed = line.trim().trim_start_matches("./");
        if trimmed.is_empty() {
            continue;
        }
        *counts.entry(trimmed.to_string()).or_insert(0) += 1;
    }
    counts
}

pub(crate) fn run_bug_dependency_drift(
    scope_files: Vec<String>,
    _workspace_path: &str,
) -> Result<Value, String> {
    let manifests = [
        "Package.swift",
        "Package.resolved",
        "package.json",
        "package-lock.json",
        "pnpm-lock.yaml",
        "yarn.lock",
        "Podfile.lock",
        "go.mod",
        "Cargo.lock",
    ];
    let changed: Vec<&String> = scope_files
        .iter()
        .filter(|f| {
            PathBuf::from(f)
                .file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|name| manifests.iter().any(|&m| m == name))
        })
        .collect();
    if changed.is_empty() {
        return Ok(make_result_standard(
            "audit_bug_dependency_drift",
            vec![],
            !scope_files.is_empty(),
            "Nessun drift dependency rilevante nello scope.",
            "Drift.",
            json!({"signal_type":"pattern","promotion_gate":"strict_verified"}),
        ));
    }
    let evidence = changed.iter().map(|s| s.as_str()).collect::<Vec<_>>().join(", ");
    let finding = make_finding(
        "warning",
        "regression",
        "bugHunter",
        changed[0].as_str(),
        None,
        "Drift di dependency/lockfile rilevato senza verifica funzionale esplicita nello scope.",
        "Verifica note di release, advisory, smoke test e regression test sulle aree colpite dalle dependency aggiornate.",
        Some(0.72),
        Some(&evidence),
        false,
        Some("audit_bug_dependency_drift".to_string()),
    );
    Ok(make_result_standard(
        "audit_bug_dependency_drift",
        vec![finding],
        true,
        "Nessun drift.",
        "Rilevato drift di dependency o lockfile nello scope corrente.",
        json!({"signal_type":"pattern","verification_hint":"Conferma se le dependency cambiate toccano runtime critici o flaky","promotion_gate":"strict_verified"}),
    ))
}

pub(crate) fn run_bug_diff_semantics(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let mut findings = Vec::new();
    for file in &scope_files {
        let Ok(output) = Command::new("/usr/bin/git")
            .args(["diff", "--unified=0", "--", file])
            .current_dir(workspace_path)
            .output()
        else {
            continue;
        };
        if !output.status.success() {
            continue;
        }
        let diff = String::from_utf8_lossy(&output.stdout).to_lowercase();
        if diff.contains("+public func")
            || diff.contains("-public func")
            || diff.contains("+open func")
            || diff.contains("-open func")
        {
            findings.push(make_finding(
                "critical",
                "regression",
                "bugHunter",
                file,
                None,
                "Semantic diff indica breaking change nel contratto pubblico.",
                "Conferma backward compatibility, test di regressione e documentazione del change.",
                Some(0.88),
                Some("public API signature change in git diff"),
                true,
                Some("audit_bug_diff_semantics".to_string()),
            ));
        } else if diff.contains("+import ") || diff.contains("-import ") {
            findings.push(make_finding(
                "warning",
                "regression",
                "bugHunter",
                file,
                None,
                "Semantic diff indica change non cosmetico da verificare.",
                "Conferma backward compatibility, test di regressione e documentazione del change.",
                Some(0.71),
                Some("import change in git diff"),
                false,
                Some("audit_bug_diff_semantics".to_string()),
            ));
        }
    }

    let meta = json!({
        "signal_type":"semantic",
        "verification_hint":"Conferma backward compatibility e test di regressione per i semantic changes rilevati",
        "promotion_gate":"strict_verified",
        "behavioral_impact": if findings.iter().any(|f| f.get("blocking").and_then(|b| b.as_bool()) == Some(true)) { "breaking_change" } else if findings.is_empty() { "none" } else { "behavior_change" }
    });

    Ok(make_result_standard(
        "audit_bug_diff_semantics",
        findings,
        !scope_files.is_empty(),
        "Nessun semantic drift rilevante dal diff corrente.",
        "Semantic diff ha rilevato cambi non cosmetici.",
        meta,
    ))
}
