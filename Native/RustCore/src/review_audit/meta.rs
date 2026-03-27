use super::dispatch::{bug_hunt_deep_tools, dispatch_standard_audit, security_deep_tools};
use super::helpers::pack_payload;
use super::merge::merge_audit_results;
use serde_json::{json, Value};

pub(crate) fn run_audit_profile(
    scope_files: Vec<String>,
    workspace_path: &str,
    profile_raw: Option<&str>,
) -> Result<Value, String> {
    let profile = profile_raw
        .unwrap_or("quick")
        .trim()
        .to_lowercase()
        .replace('-', "_");
    let tools: &[&str] = match profile.as_str() {
        "quick" => &[
            "audit_security_patterns",
            "audit_bug_diff_risks",
            "audit_bug_test_impact",
        ],
        "security_deep" | "securitydeep" => security_deep_tools(),
        "bug_hunt_deep" | "bughuntdeep" | "bug_hunt" => bug_hunt_deep_tools(),
        "release_gate" | "releasegate" => &[
            "audit_security_supply_chain",
            "audit_bug_diff_semantics",
            "audit_bug_test_impact",
        ],
        "ios_preflight" | "iospreflight" => &[
            "audit_security_surface",
            "audit_security_crypto",
            "audit_bug_concurrency",
        ],
        "backend_regression" | "backendregression" => &[
            "audit_security_dataflow",
            "audit_bug_error_handling",
            "audit_bug_api_contracts",
            "audit_bug_diff_semantics",
        ],
        _ => &[
            "audit_security_patterns",
            "audit_bug_diff_risks",
            "audit_bug_test_impact",
        ],
    };

    let mut results = Vec::new();
    for t in tools {
        results.push(dispatch_standard_audit(
            t,
            scope_files.clone(),
            workspace_path,
        )?);
    }
    Ok(merge_audit_results(
        "audit_run_profile",
        &format!("audit_run_profile.{profile}"),
        results,
    ))
}

pub(crate) fn run_correlate_findings(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let mut results = Vec::new();
    for t in security_deep_tools() {
        results.push(dispatch_standard_audit(
            t,
            scope_files.clone(),
            workspace_path,
        )?);
    }
    for t in bug_hunt_deep_tools() {
        results.push(dispatch_standard_audit(
            t,
            scope_files.clone(),
            workspace_path,
        )?);
    }
    Ok(merge_audit_results(
        "audit_correlate_findings",
        "audit_correlate_findings",
        results,
    ))
}

pub(crate) fn run_verify_bundle(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let mut results = Vec::new();
    for t in security_deep_tools() {
        results.push(dispatch_standard_audit(
            t,
            scope_files.clone(),
            workspace_path,
        )?);
    }
    for t in bug_hunt_deep_tools() {
        results.push(dispatch_standard_audit(
            t,
            scope_files.clone(),
            workspace_path,
        )?);
    }
    let merged = merge_audit_results("audit_verify_bundle_stage", "stage", results);
    let findings = merged
        .get("findings")
        .and_then(|f| f.as_array())
        .cloned()
        .unwrap_or_default();
    let strict: Vec<Value> = findings
        .into_iter()
        .filter(|f| {
            let blocking = f.get("blocking").and_then(|b| b.as_bool()) == Some(true);
            let conf = f.get("confidence").and_then(|c| c.as_f64()).unwrap_or(0.0);
            blocking || conf >= 0.75
        })
        .collect();
    let coverage = merged
        .get("coverageAvailable")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let adapters: Vec<String> = merged
        .get("adaptersUsed")
        .and_then(|a| a.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default();
    let summary = format!(
        "audit_verify_bundle: {} verified-grade finding(s).",
        strict.len()
    );
    let metadata = json!({
        "signal_type":"multi_signal",
        "verification_hint":"Solo findings ad alta confidenza o blocking; conferma ogni voce",
        "promotion_gate":"strict_verified"
    });
    Ok(pack_payload(
        "audit_verify_bundle",
        strict,
        coverage,
        summary,
        metadata,
        adapters,
        vec![],
    ))
}

pub(crate) fn run_explain_finding(params: &super::AuditParams) -> Result<Value, String> {
    let file = params.explain_file.as_deref().unwrap_or("").trim();
    let message = params.explain_message.as_deref().unwrap_or("").trim();
    if file.is_empty() || message.is_empty() {
        return Err(
            "audit_explain_finding requires 'file' and 'message' (or FFI equivalents).".to_string(),
        );
    }
    let line = params.explain_line.as_deref().unwrap_or("n/a");
    let evidence = params.explain_evidence.as_deref().unwrap_or("n/a");
    let summary = format!(
        "file: {file}\nline: {line}\nmessage: {message}\nevidence: {evidence}\ngate: strict_verified"
    );
    let metadata = json!({
        "signal_type":"manual",
        "verification_hint":"explanation_only",
        "promotion_gate":"none"
    });
    Ok(pack_payload(
        "audit_explain_finding",
        vec![],
        true,
        summary,
        metadata,
        vec![],
        vec![],
    ))
}
