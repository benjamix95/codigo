use crate::boundary::allowlist::load_allowlist;
use crate::boundary::classify::{classify_path, derive_domain, BoundaryDisposition};
use app_core_protocol::app_core::{BoundaryAuditRequest, BoundaryAuditResponse, BoundaryAuditSummary, SwiftBoundaryFinding};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

pub fn audit_request(request: BoundaryAuditRequest) -> Result<BoundaryAuditResponse, String> {
    let workspace = PathBuf::from(&request.workspace_root);
    let allowlist = load_allowlist(Path::new(&request.allowlist_path))?;
    let enforced_prefixes = normalize_prefixes(&request.enforce_legacy_zero_prefixes);
    let candidate_files = collect_candidate_files(&workspace, &request.candidate_files, &enforced_prefixes)?;
    let new_files = request.new_files.into_iter().collect::<BTreeSet<_>>();

    let mut summary = BoundaryAuditSummary::default();
    let mut findings = Vec::<SwiftBoundaryFinding>::new();
    let mut legacy_domain_counts = BTreeMap::<String, usize>::new();
    let mut enforced_prefix_counts = BTreeMap::<String, usize>::new();

    for path in candidate_files {
        match classify_path(&path, &allowlist, &new_files) {
            BoundaryDisposition::Ignored => {
                if path.ends_with(".swift") {
                    summary.ignored_swift_files += 1;
                }
            }
            BoundaryDisposition::Allowed(finding) => {
                summary.total_swift_files += 1;
                summary.allowed_swift_files += 1;
                findings.push(finding);
            }
            BoundaryDisposition::LegacyNonUi(finding) => {
                summary.total_swift_files += 1;
                summary.legacy_non_ui_files += 1;
                *legacy_domain_counts.entry(derive_domain(&finding.path)).or_insert(0) += 1;
                if let Some(prefix) = matching_enforced_prefix(&finding.path, &enforced_prefixes) {
                    summary.enforced_legacy_non_ui_files += 1;
                    *enforced_prefix_counts.entry(prefix.to_string()).or_insert(0) += 1;
                }
                findings.push(finding);
            }
            BoundaryDisposition::NewViolation(finding) => {
                summary.total_swift_files += 1;
                summary.new_non_ui_files += 1;
                findings.push(finding);
            }
        }
    }

    findings.sort_by(|lhs, rhs| lhs.path.cmp(&rhs.path));
    Ok(BoundaryAuditResponse {
        summary,
        findings,
        legacy_domain_counts,
        enforced_prefix_counts,
    })
}

pub fn format_text_report(report: &BoundaryAuditResponse) -> String {
    let mut lines = vec![
        "Rust Cutover Boundary Audit".to_string(),
        format!("Swift scansionati: {}", report.summary.total_swift_files),
        format!("Allowlist UI/bootstrap: {}", report.summary.allowed_swift_files),
        format!("Legacy non-UI: {}", report.summary.legacy_non_ui_files),
        format!("Nuove violazioni: {}", report.summary.new_non_ui_files),
        format!("Legacy hard-fail attivi: {}", report.summary.enforced_legacy_non_ui_files),
    ];

    if !report.legacy_domain_counts.is_empty() {
        lines.push("Legacy non-UI per dominio:".to_string());
        for (domain, count) in &report.legacy_domain_counts {
            lines.push(format!("- {domain}: {count}"));
        }
    }

    if !report.enforced_prefix_counts.is_empty() {
        lines.push("Legacy non-UI nei prefix hard-fail:".to_string());
        for (prefix, count) in &report.enforced_prefix_counts {
            lines.push(format!("- {prefix}: {count}"));
        }
    }

    let new_findings = report
        .findings
        .iter()
        .filter(|finding| matches!(finding.status, app_core_protocol::app_core::BoundaryFindingStatus::NewViolation));
    let mut emitted_header = false;
    for finding in new_findings {
        if !emitted_header {
            lines.push("Nuove violazioni Swift non-UI:".to_string());
            emitted_header = true;
        }
        lines.push(format!("- {}", finding.path));
        lines.push(format!("  {}", finding.reason));
    }

    lines.join("\n")
}

fn collect_candidate_files(
    workspace: &Path,
    candidate_files: &[String],
    enforced_prefixes: &[String],
) -> Result<Vec<String>, String> {
    if !candidate_files.is_empty() {
        let mut collected = candidate_files
            .iter()
            .map(|file| file.trim().trim_start_matches("./").to_string())
            .filter(|file| !file.is_empty())
            .collect::<BTreeSet<_>>();
        collect_enforced_prefix_files(workspace, enforced_prefixes, &mut collected)?;
        return Ok(collected.into_iter().collect());
    }

    let mut output = Vec::new();
    walk_swift_files(workspace, workspace, &mut output)?;
    output.sort();
    Ok(output)
}

fn collect_enforced_prefix_files(
    workspace: &Path,
    prefixes: &[String],
    output: &mut BTreeSet<String>,
) -> Result<(), String> {
    for prefix in prefixes {
        let path = workspace.join(prefix);
        if !path.exists() {
            continue;
        }
        if path.is_dir() {
            let mut scoped = Vec::new();
            walk_swift_files(workspace, &path, &mut scoped)?;
            output.extend(scoped);
            continue;
        }
        if prefix.ends_with(".swift") {
            output.insert(prefix.clone());
        }
    }
    Ok(())
}

fn walk_swift_files(root: &Path, current: &Path, output: &mut Vec<String>) -> Result<(), String> {
    for entry in fs::read_dir(current)
        .map_err(|error| format!("Impossibile leggere directory {}: {error}", current.display()))?
    {
        let entry = entry.map_err(|error| format!("Impossibile leggere entry {}: {error}", current.display()))?;
        let path = entry.path();
        let relative = path
            .strip_prefix(root)
            .map_err(|error| format!("Impossibile relativizzare {}: {error}", path.display()))?;
        let relative_string = relative.to_string_lossy().replace('\\', "/");
        if should_skip_dir(&path, &relative_string) {
            continue;
        }
        if path.is_dir() {
            walk_swift_files(root, &path, output)?;
        } else if relative_string.ends_with(".swift") {
            output.push(relative_string);
        }
    }
    Ok(())
}

fn should_skip_dir(path: &Path, relative: &str) -> bool {
    path.is_dir()
        && ["Native/target", ".build", ".xcodebuild", "tmp", "DerivedData"]
            .iter()
            .any(|prefix| relative == *prefix || relative.starts_with(&format!("{prefix}/")))
}

fn normalize_prefixes(prefixes: &[String]) -> Vec<String> {
    prefixes
        .iter()
        .map(|prefix| prefix.trim().trim_start_matches("./").trim_end_matches('/').to_string())
        .filter(|prefix| !prefix.is_empty())
        .collect()
}

fn matching_enforced_prefix<'a>(path: &str, prefixes: &'a [String]) -> Option<&'a str> {
    prefixes
        .iter()
        .find(|prefix| path == prefix.as_str() || path.starts_with(&format!("{prefix}/")))
        .map(String::as_str)
}
