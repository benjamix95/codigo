use crate::review_models::ReviewCoreErrorPayload;
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::process::Command;

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelGitContextRequest {
    pub schema_version: i32,
    pub workspace_path: String,
    pub limit: Option<usize>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelGitContextResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub branches: Vec<ReviewPanelGitBranch>,
    pub remotes: Vec<ReviewPanelGitBranch>,
    pub commits: Vec<ReviewPanelGitCommit>,
    pub current_branch: String,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelGitBranch {
    pub name: String,
    pub is_current: bool,
    pub is_remote_tracking: bool,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelGitCommit {
    pub sha: String,
    pub short_sha: String,
    pub subject: String,
    pub author_name: String,
    pub relative_date: String,
}

pub fn load_git_context(request: ReviewPanelGitContextRequest) -> ReviewPanelGitContextResponse {
    if request.workspace_path.trim().is_empty() {
        return ReviewPanelGitContextResponse::error(
            "missing_workspace",
            "workspacePath is required",
        );
    }
    let limit = request.limit.unwrap_or(50);
    let git_root = match run_git(&["rev-parse", "--show-toplevel"], &request.workspace_path) {
        Ok(output) => output.trim().to_string(),
        Err(message) => return ReviewPanelGitContextResponse::error("git_root_failed", &message),
    };

    let current_branch = current_branch(&git_root).unwrap_or_default();
    let branches = local_branches(&git_root, &current_branch).unwrap_or_default();
    let remotes = remote_branches(&git_root).unwrap_or_default();
    let commits = commit_history(&git_root, limit).unwrap_or_default();

    ReviewPanelGitContextResponse {
        schema_version: 1,
        error: None,
        branches,
        remotes,
        commits,
        current_branch,
    }
}

impl ReviewPanelGitContextResponse {
    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            branches: Vec::new(),
            remotes: Vec::new(),
            commits: Vec::new(),
            current_branch: String::new(),
        }
    }
}

fn current_branch(git_root: &str) -> Result<String, String> {
    let branch = run_git(&["branch", "--show-current"], git_root)?
        .trim()
        .to_string();
    if !branch.is_empty() {
        return Ok(branch);
    }
    let detached = run_git(&["rev-parse", "--short", "HEAD"], git_root)?
        .trim()
        .to_string();
    Ok(if detached.is_empty() {
        "(detached)".to_string()
    } else {
        format!("detached@{detached}")
    })
}

fn local_branches(
    git_root: &str,
    current_branch: &str,
) -> Result<Vec<ReviewPanelGitBranch>, String> {
    let output = run_git(
        &[
            "for-each-ref",
            "--format=%(refname:short)|%(upstream:short)",
            "refs/heads",
        ],
        git_root,
    )?;
    let mut branches = output
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| {
            let mut parts = line.splitn(2, '|');
            let name = parts.next().unwrap_or_default().to_string();
            let upstream = parts.next().unwrap_or_default().to_string();
            ReviewPanelGitBranch {
                is_current: name == current_branch,
                is_remote_tracking: !upstream.is_empty(),
                name,
            }
        })
        .collect::<Vec<_>>();
    branches.sort_by(|lhs, rhs| {
        lhs.is_current
            .cmp(&rhs.is_current)
            .reverse()
            .then_with(|| lhs.name.cmp(&rhs.name))
    });
    Ok(branches)
}

fn remote_branches(git_root: &str) -> Result<Vec<ReviewPanelGitBranch>, String> {
    let output = run_git(&["branch", "-r", "--format=%(refname:short)"], git_root)?;
    Ok(output
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.contains("HEAD"))
        .map(|name| ReviewPanelGitBranch {
            name: name.to_string(),
            is_current: false,
            is_remote_tracking: true,
        })
        .collect())
}

fn commit_history(git_root: &str, limit: usize) -> Result<Vec<ReviewPanelGitCommit>, String> {
    let format = "%H|%h|%an|%ar|%s";
    let output = run_git(
        &["log", &format!("--format={format}"), &format!("-{limit}")],
        git_root,
    )?;
    Ok(output
        .lines()
        .filter(|line| !line.trim().is_empty())
        .filter_map(|line| {
            let parts = line.splitn(5, '|').map(str::to_string).collect::<Vec<_>>();
            (parts.len() == 5).then(|| ReviewPanelGitCommit {
                sha: parts[0].clone(),
                short_sha: parts[1].clone(),
                author_name: parts[2].clone(),
                relative_date: parts[3].clone(),
                subject: parts[4].clone(),
            })
        })
        .collect())
}

fn run_git(args: &[&str], cwd: &str) -> Result<String, String> {
    let output = Command::new("git")
        .args(args)
        .current_dir(Path::new(cwd))
        .output()
        .map_err(|error| error.to_string())?;
    if output.status.success() {
        return Ok(String::from_utf8_lossy(&output.stdout).to_string());
    }
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if stderr.is_empty() {
        Err(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        Err(stderr)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_branch_output() {
        let mut branches = local_branches_from_output("main", "main|origin/main\nfeat-x|\n");
        branches.sort_by(|lhs, rhs| lhs.name.cmp(&rhs.name));
        assert_eq!(branches.len(), 2);
        assert_eq!(branches[1].name, "main");
        assert!(branches[1].is_current);
        assert!(branches[1].is_remote_tracking);
    }

    #[test]
    fn parses_commit_history_output() {
        let commits = commit_history_from_output("sha1|abc123|Alice|2 hours ago|Fix bug\n");
        assert_eq!(commits.len(), 1);
        assert_eq!(commits[0].short_sha, "abc123");
        assert_eq!(commits[0].subject, "Fix bug");
    }

    fn local_branches_from_output(current_branch: &str, output: &str) -> Vec<ReviewPanelGitBranch> {
        output
            .lines()
            .filter(|line| !line.trim().is_empty())
            .map(|line| {
                let mut parts = line.splitn(2, '|');
                let name = parts.next().unwrap_or_default().to_string();
                let upstream = parts.next().unwrap_or_default().to_string();
                ReviewPanelGitBranch {
                    is_current: name == current_branch,
                    is_remote_tracking: !upstream.is_empty(),
                    name,
                }
            })
            .collect()
    }

    fn commit_history_from_output(output: &str) -> Vec<ReviewPanelGitCommit> {
        output
            .lines()
            .filter_map(|line| {
                let parts = line.splitn(5, '|').map(str::to_string).collect::<Vec<_>>();
                (parts.len() == 5).then(|| ReviewPanelGitCommit {
                    sha: parts[0].clone(),
                    short_sha: parts[1].clone(),
                    author_name: parts[2].clone(),
                    relative_date: parts[3].clone(),
                    subject: parts[4].clone(),
                })
            })
            .collect()
    }
}
