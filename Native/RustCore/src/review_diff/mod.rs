mod git;

use git::diff_summaries;
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewDiffSummaryRequest {
    pub schema_version: i32,
    pub snapshot: Value,
    pub workspace_path: String,
    pub file_filter: Option<String>,
    pub filtered_files: Option<Vec<String>>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewDiffSummaryResponse {
    pub schema_version: i32,
    pub error: Option<ReviewDiffSummaryError>,
    pub summary: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewDiffSummaryError {
    pub code: String,
    pub message: String,
}

pub fn render_summary(request: ReviewDiffSummaryRequest) -> Result<String, String> {
    let session_id = request
        .snapshot
        .get("sessionId")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    let scope = request
        .snapshot
        .get("scope")
        .ok_or_else(|| "missing_scope".to_string())?;
    let scope_files = scope
        .get("files")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::to_string)
        .collect::<Vec<_>>();
    let target_files = request
        .filtered_files
        .unwrap_or_else(|| filter_scope_files(scope_files, request.file_filter.as_deref()));
    if target_files.is_empty() {
        return Ok("No files available for diff summary.".to_string());
    }

    let summaries = diff_summaries(scope, &request.workspace_path, &target_files)?;
    if summaries.is_empty() {
        return Ok("No diff data available for the selected review scope.".to_string());
    }

    let total_additions: i32 = summaries.iter().map(|item| item.additions).sum();
    let total_deletions: i32 = summaries.iter().map(|item| item.deletions).sum();
    let mut lines = Vec::with_capacity(summaries.len() + 1);
    lines.push(format!(
        "Diff summary for session {}: {} files, +{} / -{}",
        session_id,
        summaries.len(),
        total_additions,
        total_deletions
    ));
    lines.extend(summaries.into_iter().map(|item| {
        format!(
            "{} | +{} / -{}",
            item.file_path, item.additions, item.deletions
        )
    }));
    Ok(lines.join("\n"))
}

impl ReviewDiffSummaryResponse {
    pub fn success(summary: String) -> Self {
        Self {
            schema_version: 1,
            error: None,
            summary,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewDiffSummaryError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            summary: String::new(),
        }
    }
}

fn filter_scope_files(files: Vec<String>, file_filter: Option<&str>) -> Vec<String> {
    let needle = file_filter.unwrap_or("").trim();
    if needle.is_empty() {
        return files;
    }
    files
        .into_iter()
        .filter(|item| item.contains(needle))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::Path;
    use std::process::Command;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn renders_against_ref_summary_for_renamed_file() {
        let repo = make_repo();
        run_git_checked(&["init", "-q"], &repo);
        run_git_checked(&["config", "user.email", "review-tests@example.com"], &repo);
        run_git_checked(&["config", "user.name", "Review Tests"], &repo);
        fs::create_dir_all(repo.join("Sources")).unwrap();
        fs::write(repo.join("Sources/Old.swift"), "print(\"before\")\n").unwrap();
        run_git_checked(&["add", "Sources/Old.swift"], &repo);
        run_git_checked(&["commit", "-qm", "initial"], &repo);
        run_git_checked(&["mv", "Sources/Old.swift", "Sources/New.swift"], &repo);
        fs::write(
            repo.join("Sources/New.swift"),
            "print(\"before\")\nprint(\"after\")\n",
        )
        .unwrap();
        run_git_checked(&["commit", "-am", "rename"], &repo);

        let summary = render_summary(ReviewDiffSummaryRequest {
            schema_version: 1,
            snapshot: serde_json::json!({
                "sessionId": "session-1",
                "scope": { "type": "against_ref", "files": ["Sources/New.swift"], "ref": "HEAD~1" }
            }),
            workspace_path: repo.to_string_lossy().into_owned(),
            file_filter: None,
            filtered_files: None,
        })
        .unwrap();

        assert!(summary.contains("Sources/New.swift"));
        assert!(summary.contains("+1 / -0"));
    }

    #[test]
    fn counts_untracked_files_for_uncommitted_scope() {
        let repo = make_repo();
        run_git_checked(&["init", "-q"], &repo);
        run_git_checked(&["config", "user.email", "review-tests@example.com"], &repo);
        run_git_checked(&["config", "user.name", "Review Tests"], &repo);
        fs::write(repo.join("README.md"), "# Temp repo\n").unwrap();
        run_git_checked(&["add", "README.md"], &repo);
        run_git_checked(&["commit", "-qm", "initial"], &repo);
        fs::write(repo.join("scratch.swift"), "let a = 1\nlet b = 2\n").unwrap();

        let summary = render_summary(ReviewDiffSummaryRequest {
            schema_version: 1,
            snapshot: serde_json::json!({
                "sessionId": "session-2",
                "scope": { "type": "uncommitted", "files": ["scratch.swift"], "ref": null }
            }),
            workspace_path: repo.to_string_lossy().into_owned(),
            file_filter: None,
            filtered_files: None,
        })
        .unwrap();

        assert!(summary.contains("scratch.swift"));
        assert!(summary.contains("+2 / -0"));
    }

    fn make_repo() -> std::path::PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let repo = std::env::temp_dir().join(format!("review-diff-{nanos}"));
        fs::create_dir_all(&repo).unwrap();
        repo
    }

    fn run_git_checked(arguments: &[&str], repo: &Path) {
        let output = Command::new("/usr/bin/git")
            .args(arguments)
            .current_dir(repo)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "git {:?} failed: {}",
            arguments,
            String::from_utf8_lossy(&output.stderr)
        );
    }
}
