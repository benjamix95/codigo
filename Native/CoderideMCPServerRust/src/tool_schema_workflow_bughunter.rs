//! JSON Schema MCP per `coderide_bughunter_*`.

use crate::tool_json_schema::{object_from_props, SchemaProp};

static BUG_START: &[SchemaProp] = &[
    SchemaProp::with_enum(
        "source_kind",
        "What to scan.",
        &["uncommitted", "commit", "commit_window", "branch_window"],
    ),
    SchemaProp::with_desc("git_root", "Repository root path."),
    SchemaProp::with_desc(
        "primary_commit",
        "Commit SHA for commit or commit_window runs.",
    ),
    SchemaProp::with_desc("branch_name", "Branch for branch_window."),
    SchemaProp::with_desc("conversation_id", "Optional conversation UUID."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

static BUG_STATUS_FINDINGS: &[SchemaProp] = &[
    SchemaProp::with_desc("run_id", "BugHunter run id returned by start."),
    SchemaProp::with_desc("conversation_id", "Optional conversation UUID."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
    SchemaProp::with_enum("kind", "verified or candidate.", &["verified", "candidate"]),
    SchemaProp::with_enum(
        "severity",
        "Filter severity.",
        &["critical", "warning", "suggestion", "info"],
    ),
    SchemaProp::with_desc("status", "Optional status filter."),
];

static BUG_RUN_ID: &[SchemaProp] = &[
    SchemaProp::with_desc("run_id", "BugHunter run id (required)."),
    SchemaProp::with_desc("conversation_id", "Optional conversation UUID."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

static BUG_COMMIT_WINDOW: &[SchemaProp] = &[
    SchemaProp::with_desc("git_root", "Repository root."),
    SchemaProp::with_desc("primary_commit", "Primary commit SHA."),
    SchemaProp::with_desc("conversation_id", "Optional conversation UUID."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

static GIT_ROOT_ONLY: &[SchemaProp] =
    &[SchemaProp::with_desc("git_root", "Repository root for hooks.")];

static BUG_RUN_HISTORY: &[SchemaProp] = &[
    SchemaProp::with_desc("conversation_id", "Optional conversation filter."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

static BUG_FALLBACK: &[SchemaProp] = &[
    SchemaProp::with_desc("run_id", "BugHunter run id."),
    SchemaProp::with_desc("conversation_id", "Optional conversation UUID."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

pub fn bughunter_tool_schema(name: &str) -> serde_json::Value {
    match name {
        "coderide_bughunter_start" => object_from_props(BUG_START, &[]),
        "coderide_bughunter_status" | "coderide_bughunter_findings" => {
            object_from_props(BUG_STATUS_FINDINGS, &[])
        }
        "coderide_bughunter_autofix_preview"
        | "coderide_bughunter_autofix_apply"
        | "coderide_bughunter_autofix_commit"
        | "coderide_bughunter_explain_cluster"
        | "coderide_bughunter_cancel_run" => object_from_props(BUG_RUN_ID, &["run_id"]),
        "coderide_bughunter_commit_window" => {
            object_from_props(BUG_COMMIT_WINDOW, &["git_root", "primary_commit"])
        }
        "coderide_bughunter_install_hook" | "coderide_bughunter_uninstall_hook" => {
            object_from_props(GIT_ROOT_ONLY, &["git_root"])
        }
        "coderide_bughunter_run_history" => object_from_props(BUG_RUN_HISTORY, &[]),
        _ => object_from_props(BUG_FALLBACK, &[]),
    }
}
