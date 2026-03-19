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
pub struct ReviewPatchOpenPrExecutionContextRequest {
    pub schema_version: i32,
    pub finding_id: String,
    pub artifact_base_branch_name: Option<String>,
    pub current_branch_name: String,
    pub existing_branch_name: Option<String>,
    pub worktree_root: String,
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
pub struct ReviewPatchMergeExecutionContextRequest {
    pub schema_version: i32,
    pub pr_url: Option<String>,
    pub safe_only: bool,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchResolveConflictsResultRequest {
    pub schema_version: i32,
    pub patch_id: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchResolveConflictsContextRequest {
    pub schema_version: i32,
    pub worktree_path: Option<String>,
    pub branch_name: Option<String>,
    pub base_branch_name: Option<String>,
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
pub struct ReviewPatchResolveConflictsContextResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: Option<String>,
    pub worktree_path: Option<String>,
    pub branch_name: Option<String>,
    pub base_branch_name: Option<String>,
    pub commit_message: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchOpenPrExecutionContextResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: Option<String>,
    pub branch_name: Option<String>,
    pub base_branch_name: Option<String>,
    pub worktree_path: Option<String>,
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
pub struct ReviewPatchMergeExecutionContextResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: Option<String>,
    pub pr_url: Option<String>,
    pub first_merge_auto: Option<bool>,
    pub retry_after_conflicts: Option<bool>,
    pub retry_merge_auto: Option<bool>,
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

impl ReviewPatchResolveConflictsContextResponse {
    pub fn success(
        worktree_path: String,
        branch_name: String,
        base_branch_name: String,
        commit_message: String,
    ) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: None,
            worktree_path: Some(worktree_path),
            branch_name: Some(branch_name),
            base_branch_name: Some(base_branch_name),
            commit_message: Some(commit_message),
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: Some(message.into()),
            worktree_path: None,
            branch_name: None,
            base_branch_name: None,
            commit_message: None,
        }
    }
}

impl ReviewPatchOpenPrExecutionContextResponse {
    pub fn success(branch_name: String, base_branch_name: String, worktree_path: String) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: None,
            branch_name: Some(branch_name),
            base_branch_name: Some(base_branch_name),
            worktree_path: Some(worktree_path),
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: Some(message.into()),
            branch_name: None,
            base_branch_name: None,
            worktree_path: None,
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

impl ReviewPatchMergeExecutionContextResponse {
    pub fn success(
        pr_url: String,
        first_merge_auto: bool,
        retry_after_conflicts: bool,
        retry_merge_auto: bool,
    ) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: None,
            pr_url: Some(pr_url),
            first_merge_auto: Some(first_merge_auto),
            retry_after_conflicts: Some(retry_after_conflicts),
            retry_merge_auto: Some(retry_merge_auto),
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: Some(message.into()),
            pr_url: None,
            first_merge_auto: None,
            retry_after_conflicts: None,
            retry_merge_auto: None,
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
