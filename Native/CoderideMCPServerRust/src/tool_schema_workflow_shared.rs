//! Proprietà JSON Schema condivise tra review e security workflow.

use crate::tool_json_schema::SchemaProp;

static SESSION_SCOPE_PROPS: &[SchemaProp] = &[
    SchemaProp::with_desc("session_id", "Owning review or security session id."),
    SchemaProp::with_desc("sessionId", "Alias of session_id."),
    SchemaProp::with_desc("conversation_id", "Conversation UUID for scoped sessions."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

static FINDING_PATCH_PROPS: &[SchemaProp] = &[
    SchemaProp::with_desc("finding_id", "Finding id in the VerifiedFindings snapshot."),
    SchemaProp::with_desc("session_id", "Session that owns the finding."),
    SchemaProp::with_desc("sessionId", "Alias of session_id."),
    SchemaProp::with_desc("conversation_id", "Conversation UUID when sessions are scoped."),
    SchemaProp::with_desc("conversationId", "Alias of conversation_id."),
];

pub fn session_scope_props() -> &'static [SchemaProp] {
    SESSION_SCOPE_PROPS
}

pub fn finding_patch_props() -> &'static [SchemaProp] {
    FINDING_PATCH_PROPS
}

pub const FINDING_PATCH_REQUIRED: &[&str] = &["finding_id", "session_id"];
