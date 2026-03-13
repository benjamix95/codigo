use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(tag = "type", content = "payload", rename_all = "snake_case")]
pub enum AppCoreRequest {
    BoundaryAudit(BoundaryAuditRequest),
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(tag = "type", content = "payload", rename_all = "snake_case")]
pub enum AppCoreResponse {
    BoundaryAudit(BoundaryAuditResponse),
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
pub struct BoundaryAuditRequest {
    pub workspace_root: String,
    pub allowlist_path: String,
    #[serde(default)]
    pub candidate_files: Vec<String>,
    #[serde(default)]
    pub new_files: Vec<String>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
pub struct BoundaryAuditSummary {
    pub total_swift_files: usize,
    pub ignored_swift_files: usize,
    pub allowed_swift_files: usize,
    pub legacy_non_ui_files: usize,
    pub new_non_ui_files: usize,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum BoundaryFindingStatus {
    Allowed,
    LegacyNonUi,
    NewViolation,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SwiftBoundaryKind {
    UiView,
    BindingAdapter,
    AppleBootstrap,
    LegacyNonUi,
    Ignored,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct SwiftBoundaryFinding {
    pub path: String,
    pub status: BoundaryFindingStatus,
    pub kind: SwiftBoundaryKind,
    pub reason: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
pub struct BoundaryAuditResponse {
    pub summary: BoundaryAuditSummary,
    #[serde(default)]
    pub findings: Vec<SwiftBoundaryFinding>,
    #[serde(default)]
    pub legacy_domain_counts: BTreeMap<String, usize>,
}
