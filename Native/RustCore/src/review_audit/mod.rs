//! Audit statici per review core (parity con tool catalog MCP `coderide_audit_*`).

mod bugs;
mod dispatch;
mod helpers;
mod merge;
mod meta;
mod security;

use dispatch::dispatch_standard_audit;
use serde_json::Value;

#[derive(Default, Clone, Debug)]
pub struct AuditParams {
    pub profile: Option<String>,
    pub explain_file: Option<String>,
    pub explain_message: Option<String>,
    pub explain_line: Option<String>,
    pub explain_evidence: Option<String>,
}

impl From<&crate::review_models::ReviewAuditRequest> for AuditParams {
    fn from(r: &crate::review_models::ReviewAuditRequest) -> Self {
        Self {
            profile: r.profile.clone(),
            explain_file: r.file.clone(),
            explain_message: r.message.clone(),
            explain_line: r.line.clone(),
            explain_evidence: r.evidence.clone(),
        }
    }
}

pub fn run_audit(
    tool_name: &str,
    scope_files: Vec<String>,
    workspace_path: &str,
    params: AuditParams,
) -> Result<Value, String> {
    match tool_name {
        "audit_run_profile" => {
            meta::run_audit_profile(scope_files, workspace_path, params.profile.as_deref())
        }
        "audit_correlate_findings" => meta::run_correlate_findings(scope_files, workspace_path),
        "audit_verify_bundle" => meta::run_verify_bundle(scope_files, workspace_path),
        "audit_explain_finding" => meta::run_explain_finding(&params),
        other => dispatch_standard_audit(other, scope_files, workspace_path),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn dataflow_audit_detects_source_sink() {
        let root = std::env::temp_dir().join(format!(
            "review-audit-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(
            root.join("Service.swift"),
            "let input = request.query[\"cmd\"]\nrunProcess(input, shell: true)\n",
        )
        .unwrap();
        let result = run_audit(
            "audit_security_dataflow",
            vec!["Service.swift".to_string()],
            root.to_str().unwrap(),
            AuditParams::default(),
        )
        .unwrap();
        assert!(!result["findings"].as_array().unwrap().is_empty());
    }

    #[test]
    fn bug_audits_support_state_machine_error_handling_and_test_gaps() {
        let root = std::env::temp_dir().join(format!(
            "review-audit-bug-tools-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(root.join("Sources")).unwrap();
        std::fs::write(
            root.join("Sources/Flow.swift"),
            "enum ViewState { case idle, loading, done }\nstate = .idle\nstate = .loading\nstate = .done\ncatch {}\n",
        )
        .unwrap();

        let state_machine = run_audit(
            "audit_bug_state_machine",
            vec!["Sources/Flow.swift".to_string()],
            root.to_str().unwrap(),
            AuditParams::default(),
        )
        .unwrap();
        assert_eq!(
            state_machine["toolName"].as_str(),
            Some("audit_bug_state_machine")
        );
        assert!(!state_machine["findings"].as_array().unwrap().is_empty());

        let error_handling = run_audit(
            "audit_bug_error_handling",
            vec!["Sources/Flow.swift".to_string()],
            root.to_str().unwrap(),
            AuditParams::default(),
        )
        .unwrap();
        assert_eq!(
            error_handling["toolName"].as_str(),
            Some("audit_bug_error_handling")
        );
        assert!(!error_handling["findings"].as_array().unwrap().is_empty());

        let test_gaps = run_audit(
            "audit_bug_test_gaps",
            vec!["Sources/Flow.swift".to_string()],
            root.to_str().unwrap(),
            AuditParams::default(),
        )
        .unwrap();
        assert_eq!(test_gaps["toolName"].as_str(), Some("audit_bug_test_gaps"));
        assert!(!test_gaps["findings"].as_array().unwrap().is_empty());
    }

    #[test]
    fn run_profile_quick_runs() {
        let root = std::env::temp_dir().join(format!(
            "review-audit-profile-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("a.swift"), "public func x() { try! foo() }\n").unwrap();
        let r = run_audit(
            "audit_run_profile",
            vec!["a.swift".to_string()],
            root.to_str().unwrap(),
            AuditParams {
                profile: Some("quick".into()),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(r["toolName"].as_str(), Some("audit_run_profile"));
    }

    #[test]
    fn explain_finding_requires_fields() {
        let e = run_audit(
            "audit_explain_finding",
            vec![],
            ".",
            AuditParams::default(),
        );
        assert!(e.is_err());
    }
}
