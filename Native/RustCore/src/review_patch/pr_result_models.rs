use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchOpenPrContextRequest {
    pub schema_version: i32,
    pub file_path: String,
    pub message: String,
    pub verification_report: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchOpenPrResultRequest {
    pub schema_version: i32,
    pub patch_id: String,
    pub branch_name: String,
    pub base_branch_name: String,
    pub worktree_path: String,
    pub pr_url: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchMergeResultRequest {
    pub schema_version: i32,
    pub patch_id: String,
    pub pr_url: Option<String>,
    pub success: bool,
    pub error_message: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchResolveConflictsResultRequest {
    pub schema_version: i32,
    pub patch_id: String,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchOpenPrContextResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: Option<String>,
    pub title: Option<String>,
    pub body: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchOpenPrResultResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: Option<String>,
    pub status: Option<String>,
    pub pr_status: Option<String>,
    pub branch_name: Option<String>,
    pub base_branch_name: Option<String>,
    pub worktree_path: Option<String>,
    pub pr_url: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchMergeResultResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: Option<String>,
    pub status: Option<String>,
    pub merge_status: Option<String>,
    pub pr_url: Option<String>,
    pub conflicts: Option<Vec<String>>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchResolveConflictsResultResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: Option<String>,
    pub status: Option<String>,
    pub merge_status: Option<String>,
    pub conflicts: Option<Vec<String>>,
}

impl ReviewPatchOpenPrContextResponse {
    pub fn success(title: String, body: String) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: None,
            title: Some(title),
            body: Some(body),
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: Some(message.into()),
            title: None,
            body: None,
        }
    }
}

impl ReviewPatchOpenPrResultResponse {
    pub fn success(
        status: String,
        pr_status: String,
        branch_name: String,
        base_branch_name: String,
        worktree_path: String,
        pr_url: String,
    ) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: None,
            status: Some(status),
            pr_status: Some(pr_status),
            branch_name: Some(branch_name),
            base_branch_name: Some(base_branch_name),
            worktree_path: Some(worktree_path),
            pr_url: Some(pr_url),
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: Some(message.into()),
            status: None,
            pr_status: None,
            branch_name: None,
            base_branch_name: None,
            worktree_path: None,
            pr_url: None,
        }
    }
}

impl ReviewPatchMergeResultResponse {
    pub fn success(
        status: String,
        merge_status: String,
        pr_url: Option<String>,
        conflicts: Vec<String>,
    ) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: None,
            status: Some(status),
            merge_status: Some(merge_status),
            pr_url,
            conflicts: Some(conflicts),
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: Some(message.into()),
            status: None,
            merge_status: None,
            pr_url: None,
            conflicts: None,
        }
    }
}

impl ReviewPatchResolveConflictsResultResponse {
    pub fn success(status: String, merge_status: String, conflicts: Vec<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: None,
            status: Some(status),
            merge_status: Some(merge_status),
            conflicts: Some(conflicts),
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: Some(message.into()),
            status: None,
            merge_status: None,
            conflicts: None,
        }
    }
}
