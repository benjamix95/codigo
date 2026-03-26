//! JSON Schema per tool review / security / bughunter (VerifiedFindings + code queue).

use crate::tool_json_schema::object_schema;
use serde_json::Value;

pub fn verified_workflow_schema(name: &str) -> Option<Value> {
    if name.starts_with("coderide_review_") {
        return Some(review_tool_schema(name));
    }
    if name.starts_with("coderide_security_") {
        return Some(security_tool_schema(name));
    }
    if name.starts_with("coderide_bughunter_") {
        return Some(bughunter_tool_schema(name));
    }
    None
}

fn session_scope() -> Vec<(&'static str, &'static str)> {
    vec![
        ("session_id", "string"),
        ("sessionId", "string"),
        ("conversation_id", "string"),
        ("conversationId", "string"),
    ]
}

fn finding_patch_common() -> Vec<(&'static str, &'static str)> {
    vec![
        ("finding_id", "string"),
        ("session_id", "string"),
        ("sessionId", "string"),
        ("conversation_id", "string"),
        ("conversationId", "string"),
    ]
}

fn review_tool_schema(name: &str) -> Value {
    match name {
        "coderide_review_start" => object_schema(
            &[
                ("scope", "string"),
                ("ref", "string"),
                ("max_workers", "string"),
                ("max_rounds", "string"),
                ("analysis_only", "string"),
                ("analysis_backend", "string"),
                ("execution_backend", "string"),
                ("session_id", "string"),
                ("sessionId", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
            ],
            &[],
        ),
        "coderide_review_list_sessions" => object_schema(
            &[("conversation_id", "string"), ("conversationId", "string")],
            &[],
        ),
        "coderide_review_status" => object_schema(&session_scope(), &[]),
        "coderide_review_findings" => object_schema(
            &[
                ("session_id", "string"),
                ("sessionId", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
                ("severity", "string"),
                ("kind", "string"),
                ("file", "string"),
                ("status", "string"),
                ("origin", "string"),
                ("category", "string"),
                ("limit", "string"),
            ],
            &[],
        ),
        "coderide_review_apply_fix" | "coderide_review_verify_finding" | "coderide_review_prepare_patch" | "coderide_review_preview_patch" | "coderide_review_apply_patch" | "coderide_review_verify_patch" | "coderide_review_revalidate_finding" | "coderide_review_rollback_patch" | "coderide_review_open_pr" | "coderide_review_merge_pr" | "coderide_review_resolve_conflicts" => {
            object_schema(
                &finding_patch_common(),
                &["finding_id", "session_id"],
            )
        },
        "coderide_review_close_finding" => object_schema(
            &[
                ("finding_id", "string"),
                ("session_id", "string"),
                ("sessionId", "string"),
                ("reason", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
            ],
            &["finding_id", "session_id"],
        ),
        "coderide_review_dismiss" => object_schema(
            &[
                ("finding_id", "string"),
                ("reason", "string"),
                ("session_id", "string"),
                ("sessionId", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
            ],
            &["finding_id", "session_id"],
        ),
        "coderide_review_configure" => object_schema(
            &[
                ("max_workers", "string"),
                ("max_rounds", "string"),
                ("analysis_backend", "string"),
                ("execution_backend", "string"),
                ("analysis_only", "string"),
                ("session_id", "string"),
                ("sessionId", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
            ],
            &["session_id"],
        ),
        "coderide_review_diff_summary" => object_schema(
            &[
                ("file", "string"),
                ("origin", "string"),
                ("category", "string"),
                ("session_id", "string"),
                ("sessionId", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
            ],
            &[],
        ),
        "coderide_review_comment" => object_schema(
            &[
                ("finding_id", "string"),
                ("content", "string"),
                ("author", "string"),
                ("session_id", "string"),
                ("sessionId", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
            ],
            &["finding_id", "content", "session_id"],
        ),
        "coderide_review_get_outcome" => object_schema(
            &[
                ("session_id", "string"),
                ("sessionId", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
            ],
            &["session_id"],
        ),
        _ => object_schema(
            &[
                ("finding_id", "string"),
                ("session_id", "string"),
                ("conversation_id", "string"),
            ],
            &[],
        ),
    }
}

fn security_tool_schema(name: &str) -> Value {
    match name {
        "coderide_security_start" => object_schema(
            &[
                ("scope", "string"),
                ("ref", "string"),
                ("session_id", "string"),
                ("sessionId", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
            ],
            &[],
        ),
        "coderide_security_status" => object_schema(&session_scope(), &[]),
        "coderide_security_findings" => object_schema(
            &[
                ("session_id", "string"),
                ("sessionId", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
                ("kind", "string"),
                ("severity", "string"),
                ("status", "string"),
            ],
            &[],
        ),
        "coderide_security_verify_finding" | "coderide_security_prepare_patch" | "coderide_security_preview_patch" | "coderide_security_apply_patch" | "coderide_security_verify_patch" | "coderide_security_revalidate_finding" | "coderide_security_rollback_patch" => {
            object_schema(
                &finding_patch_common(),
                &["finding_id", "session_id"],
            )
        },
        "coderide_security_close_finding" => object_schema(
            &[
                ("finding_id", "string"),
                ("session_id", "string"),
                ("sessionId", "string"),
                ("reason", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
            ],
            &["finding_id", "session_id"],
        ),
        _ => object_schema(&session_scope(), &[]),
    }
}

fn bughunter_tool_schema(name: &str) -> Value {
    match name {
        "coderide_bughunter_start" => object_schema(
            &[
                ("source_kind", "string"),
                ("git_root", "string"),
                ("primary_commit", "string"),
                ("branch_name", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
            ],
            &[],
        ),
        "coderide_bughunter_status" | "coderide_bughunter_findings" => object_schema(
            &[
                ("run_id", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
                ("kind", "string"),
                ("severity", "string"),
                ("status", "string"),
            ],
            &[],
        ),
        "coderide_bughunter_autofix_preview"
        | "coderide_bughunter_autofix_apply"
        | "coderide_bughunter_autofix_commit"
        | "coderide_bughunter_explain_cluster"
        | "coderide_bughunter_cancel_run" => object_schema(
            &[
                ("run_id", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
            ],
            &["run_id"],
        ),
        "coderide_bughunter_commit_window" => object_schema(
            &[
                ("git_root", "string"),
                ("primary_commit", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
            ],
            &["git_root", "primary_commit"],
        ),
        "coderide_bughunter_install_hook" | "coderide_bughunter_uninstall_hook" => {
            object_schema(&[("git_root", "string")], &["git_root"])
        },
        "coderide_bughunter_run_history" => object_schema(
            &[("conversation_id", "string"), ("conversationId", "string")],
            &[],
        ),
        _ => object_schema(
            &[
                ("run_id", "string"),
                ("conversation_id", "string"),
                ("conversationId", "string"),
            ],
            &[],
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::verified_workflow_schema;

    #[test]
    fn workflow_tools_from_catalog_have_non_empty_properties() {
        let raw = include_str!("tool_names.txt");
        for line in raw.lines().map(str::trim).filter(|l| !l.is_empty()) {
            if !(line.starts_with("coderide_review_")
                || line.starts_with("coderide_security_")
                || line.starts_with("coderide_bughunter_"))
            {
                continue;
            }
            let schema = verified_workflow_schema(line)
                .unwrap_or_else(|| panic!("missing workflow schema for {line}"));
            let props = schema
                .get("properties")
                .and_then(|p| p.as_object())
                .unwrap_or_else(|| panic!("{line}: no properties object"));
            assert!(!props.is_empty(), "{line}: empty properties");
        }
    }
}
