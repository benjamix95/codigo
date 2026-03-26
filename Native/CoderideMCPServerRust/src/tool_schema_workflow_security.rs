//! JSON Schema MCP per `coderide_security_*`.

use crate::tool_json_schema::{object_from_props, SchemaProp};
use crate::tool_schema_workflow_shared::{finding_patch_props, session_scope_props, FINDING_PATCH_REQUIRED};

static SECURITY_START: &[SchemaProp] = &[
    SchemaProp::with_enum(
        "scope",
        "Security review scope.",
        &["uncommitted", "staged", "against_ref"],
    ),
    SchemaProp::with_desc("ref", "Git ref when scope is against_ref."),
    SchemaProp::with_desc("session_id", "Optional unique session id."),
    SchemaProp::with_desc("sessionId", "Alias of session_id."),
    SchemaProp::with_desc("conversation_id", "Conversation UUID."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

static SECURITY_FINDINGS: &[SchemaProp] = &[
    SchemaProp::with_desc("session_id", "Security session id."),
    SchemaProp::with_desc("sessionId", "Alias of session_id."),
    SchemaProp::with_desc("conversation_id", "Conversation scope."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
    SchemaProp::with_enum("kind", "verified or candidate.", &["verified", "candidate"]),
    SchemaProp::with_enum(
        "severity",
        "Severity filter.",
        &["critical", "warning", "suggestion", "info"],
    ),
    SchemaProp::with_desc("status", "Optional status filter."),
];

static SECURITY_CLOSE: &[SchemaProp] = &[
    SchemaProp::with_desc("finding_id", "Security finding id."),
    SchemaProp::with_desc("session_id", "Owning session id."),
    SchemaProp::with_desc("sessionId", "Alias of session_id."),
    SchemaProp::with_desc("reason", "Closure reason."),
    SchemaProp::with_desc("conversation_id", "Conversation scope."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

pub fn security_tool_schema(name: &str) -> serde_json::Value {
    match name {
        "coderide_security_start" => object_from_props(SECURITY_START, &[]),
        "coderide_security_status" => object_from_props(session_scope_props(), &[]),
        "coderide_security_findings" => object_from_props(SECURITY_FINDINGS, &[]),
        "coderide_security_verify_finding"
        | "coderide_security_prepare_patch"
        | "coderide_security_preview_patch"
        | "coderide_security_apply_patch"
        | "coderide_security_verify_patch"
        | "coderide_security_revalidate_finding"
        | "coderide_security_rollback_patch" => {
            object_from_props(finding_patch_props(), FINDING_PATCH_REQUIRED)
        }
        "coderide_security_close_finding" => {
            object_from_props(SECURITY_CLOSE, &["finding_id", "session_id"])
        }
        _ => object_from_props(session_scope_props(), &[]),
    }
}
