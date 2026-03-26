//! JSON Schema MCP per `coderide_review_*`.

use crate::tool_json_schema::{object_from_props, object_schema, SchemaProp};
use crate::tool_schema_workflow_shared::{finding_patch_props, session_scope_props, FINDING_PATCH_REQUIRED};

static REVIEW_START_PROPS: &[SchemaProp] = &[
    SchemaProp::with_enum(
        "scope",
        "Review scope: working tree, staged only, or diff against a git ref.",
        &["uncommitted", "staged", "against_ref"],
    ),
    SchemaProp::with_desc(
        "ref",
        "Git ref when scope is against_ref (e.g. main, origin/develop).",
    ),
    SchemaProp::with_desc("max_workers", "Max parallel fix workers (1–12), string-encoded."),
    SchemaProp::with_desc("max_rounds", "Max review rounds (1–10), often string-encoded."),
    SchemaProp::with_desc("analysis_only", "If true, skip fix rounds (string true/false)."),
    SchemaProp::with_desc("analysis_backend", "Backend id for analysis phase."),
    SchemaProp::with_desc("execution_backend", "Backend id for execution phase."),
    SchemaProp::with_desc("session_id", "Optional unique session id; generated if omitted."),
    SchemaProp::with_desc("sessionId", "Alias of session_id."),
    SchemaProp::with_desc("conversation_id", "Conversation UUID for concurrent sessions."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

static REVIEW_LIST_SESSIONS: &[SchemaProp] = &[
    SchemaProp::with_desc("conversation_id", "Filter sessions tied to this conversation."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

static REVIEW_FINDINGS_PROPS: &[SchemaProp] = &[
    SchemaProp::with_desc("session_id", "Session to read findings from."),
    SchemaProp::with_desc("sessionId", "Alias of session_id."),
    SchemaProp::with_desc("conversation_id", "Conversation scope."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
    SchemaProp::with_enum(
        "severity",
        "Filter by severity.",
        &["critical", "warning", "suggestion", "info"],
    ),
    SchemaProp::with_enum(
        "kind",
        "verified (default) or candidate findings.",
        &["verified", "candidate"],
    ),
    SchemaProp::with_desc("file", "Substring match on file path."),
    SchemaProp::with_desc("status", "Filter by finding status (open, dismissed, etc.)."),
    SchemaProp::with_desc("origin", "reviewer, bugHunter, securityAuditor, or audit_tool."),
    SchemaProp::with_desc(
        "category",
        "correctness, regression, concurrency, security, tests, maintainability, performance, other.",
    ),
    SchemaProp::with_desc("limit", "Max rows (string integer)."),
];

static REVIEW_CLOSE: &[SchemaProp] = &[
    SchemaProp::with_desc("finding_id", "Finding id to close."),
    SchemaProp::with_desc("session_id", "Owning session id."),
    SchemaProp::with_desc("sessionId", "Alias of session_id."),
    SchemaProp::with_desc("reason", "Why the finding is closed (human-readable)."),
    SchemaProp::with_desc("conversation_id", "Conversation scope."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

static REVIEW_DISMISS: &[SchemaProp] = &[
    SchemaProp::with_desc("finding_id", "Finding id to dismiss."),
    SchemaProp::with_desc(
        "reason",
        "e.g. false_positive, wont_fix, by_design, duplicate.",
    ),
    SchemaProp::with_desc("session_id", "Owning session id."),
    SchemaProp::with_desc("sessionId", "Alias of session_id."),
    SchemaProp::with_desc("conversation_id", "Conversation scope."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

static REVIEW_CONFIGURE: &[SchemaProp] = &[
    SchemaProp::with_desc("max_workers", "Parallel workers (string integer 1–12)."),
    SchemaProp::with_desc("max_rounds", "Rounds (string integer 1–10)."),
    SchemaProp::with_desc("analysis_backend", "Analysis backend id."),
    SchemaProp::with_desc("execution_backend", "Execution backend id."),
    SchemaProp::with_desc("analysis_only", "String true/false."),
    SchemaProp::with_desc("session_id", "Session to reconfigure (required)."),
    SchemaProp::with_desc("sessionId", "Alias of session_id."),
    SchemaProp::with_desc("conversation_id", "Conversation scope."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

static REVIEW_DIFF_SUMMARY: &[SchemaProp] = &[
    SchemaProp::with_desc("file", "Optional single file; omit for whole scope."),
    SchemaProp::with_desc("origin", "Optional finding origin filter."),
    SchemaProp::with_desc("category", "Optional category filter."),
    SchemaProp::with_desc("session_id", "Session id when multiple active."),
    SchemaProp::with_desc("sessionId", "Alias of session_id."),
    SchemaProp::with_desc("conversation_id", "Conversation scope."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

static REVIEW_COMMENT: &[SchemaProp] = &[
    SchemaProp::with_desc("finding_id", "Finding to annotate."),
    SchemaProp::with_desc("content", "Comment body."),
    SchemaProp::with_desc("author", "Optional author label (default agent)."),
    SchemaProp::with_desc("session_id", "Owning session id."),
    SchemaProp::with_desc("sessionId", "Alias of session_id."),
    SchemaProp::with_desc("conversation_id", "Conversation scope."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

pub fn review_tool_schema(name: &str) -> serde_json::Value {
    match name {
        "coderide_review_start" => object_from_props(REVIEW_START_PROPS, &[]),
        "coderide_review_list_sessions" => object_from_props(REVIEW_LIST_SESSIONS, &[]),
        "coderide_review_status" => object_from_props(session_scope_props(), &[]),
        "coderide_review_findings" => object_from_props(REVIEW_FINDINGS_PROPS, &[]),
        "coderide_review_apply_fix"
        | "coderide_review_verify_finding"
        | "coderide_review_prepare_patch"
        | "coderide_review_preview_patch"
        | "coderide_review_apply_patch"
        | "coderide_review_verify_patch"
        | "coderide_review_revalidate_finding"
        | "coderide_review_rollback_patch"
        | "coderide_review_open_pr"
        | "coderide_review_merge_pr"
        | "coderide_review_resolve_conflicts" => {
            object_from_props(finding_patch_props(), FINDING_PATCH_REQUIRED)
        }
        "coderide_review_close_finding" => object_from_props(REVIEW_CLOSE, &["finding_id", "session_id"]),
        "coderide_review_dismiss" => object_from_props(REVIEW_DISMISS, &["finding_id", "session_id"]),
        "coderide_review_configure" => object_from_props(REVIEW_CONFIGURE, &["session_id"]),
        "coderide_review_diff_summary" => object_from_props(REVIEW_DIFF_SUMMARY, &[]),
        "coderide_review_comment" => {
            object_from_props(REVIEW_COMMENT, &["finding_id", "content", "session_id"])
        }
        "coderide_review_get_outcome" => object_from_props(session_scope_props(), &["session_id"]),
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
