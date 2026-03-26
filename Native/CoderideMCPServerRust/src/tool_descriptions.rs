//! Model-facing descriptions for `tools/list` — each entry explains purpose and **Usage** so the LLM can route calls.

use std::collections::HashMap;
use std::sync::OnceLock;

pub fn description_for(name: &str) -> String {
    if let Some(text) = audit_description(name) {
        return text;
    }
    static MAP: OnceLock<HashMap<String, String>> = OnceLock::new();
    let map = MAP.get_or_init(|| {
        serde_json::from_str(include_str!("tool_descriptions.json"))
            .expect("parse embedded tool_descriptions.json")
    });
    map.get(name)
        .cloned()
        .unwrap_or_else(|| format!("CoderIDE tool `{name}` — add entry to tool_descriptions.json or audit_description match."))
}

fn audit_description(name: &str) -> Option<String> {
    let suffix = name.strip_prefix("coderide_audit_")?;
    Some(format!(
        "{} Usage: optional path, scope_files or scopeFiles (JSON array or CSV), file, profile, message, line, evidence — narrow the scope for faster, focused read-only audits.",
        audit_blurb(suffix)
    ))
}

fn audit_blurb(suffix: &str) -> &'static str {
    match suffix {
        "bug_api_contracts" => "Read-only audit: API surface contracts, boundary mismatches, and unsafe assumptions across modules.",
        "bug_concurrency" => "Read-only audit: races, locks, actors, async boundaries, and shared mutable state risks.",
        "bug_dependency_drift" => "Read-only audit: dependency/version skew vs lockfiles and expected toolchain baselines.",
        "bug_diff_risks" => "Read-only audit: risky patterns introduced by recent diffs (focused churn analysis).",
        "bug_diff_semantics" => "Read-only audit: semantic behavior shifts in diffs (logic drift, unintended changes).",
        "bug_error_handling" => "Read-only audit: error propagation, Result/throws gaps, swallowed errors, and recovery paths.",
        "bug_hotspots" => "Read-only audit: complexity hotspots, churn-heavy files, and fragile regions.",
        "bug_nil_crash_paths" => "Read-only audit: null/optional mishandling and likely crash paths (force-unwrap, unchecked).",
        "bug_state_machine" => "Read-only audit: state machines, invalid transitions, and lifecycle edge cases.",
        "bug_test_gaps" => "Read-only audit: missing or shallow tests for critical logic and regressions.",
        "bug_test_impact" => "Read-only audit: test coverage vs recent changes; tests that should exist for touched code.",
        "correlate_findings" => "Read-only audit helper: correlate multiple findings into clusters/themes (meta-analysis).",
        "explain_finding" => "Read-only audit helper: produce a structured explanation for one audit finding.",
        "run_profile" => "Execute a named read-only audit profile bundle (host-defined grouping of checks).",
        "security_authz" => "Read-only security audit: authorization, access control, privilege checks, and IDOR patterns.",
        "security_crypto" => "Read-only security audit: cryptography misuse, weak algorithms, and secret handling in code.",
        "security_dataflow" => "Read-only security audit: sensitive data flow, logging leaks, and exfiltration patterns.",
        "security_dependencies" => "Read-only security audit: vulnerable or suspicious dependency usage and supply signals.",
        "security_deserialization" => "Read-only security audit: deserialization boundaries and injection/unsafe object graphs.",
        "security_patterns" => "Read-only security audit: OWASP-style pattern scan (SQLi, XSS hooks, command injection shapes).",
        "security_secrets" => "Read-only security audit: hard-coded secrets, tokens, keys, and unsafe credential patterns.",
        "security_supply_chain" => "Read-only security audit: supply-chain and third-party risk surfacing in the workspace.",
        "security_surface" => "Read-only security audit: attack surface expansion (new endpoints, parsers, IPC).",
        "verify_bundle" => "Read-only audit: validate a prior audit bundle/export for consistency and completeness.",
        _ => "Read-only structured workspace audit for this checklist. Prefer scoping to changed files when possible.",
    }
}

#[cfg(test)]
mod tests {
    use super::description_for;
    use std::collections::HashSet;

    #[test]
    fn every_tool_name_has_usage_and_is_not_placeholder() {
        let raw = include_str!("tool_names.txt");
        let names: HashSet<_> = raw.lines().map(str::trim).filter(|l| !l.is_empty()).collect();
        for name in &names {
            let d = description_for(name);
            assert!(
                d.contains("Usage:"),
                "{name}: description must include a Usage clause for model routing"
            );
            assert!(
                !d.contains("Rust-migrated"),
                "{name}: stale placeholder description"
            );
            assert!(d.len() >= 40, "{name}: description unexpectedly short");
        }
    }
}
