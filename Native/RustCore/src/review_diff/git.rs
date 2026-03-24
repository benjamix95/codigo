use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;
use std::process::Command;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FileSummary {
    pub file_path: String,
    pub additions: i32,
    pub deletions: i32,
}

pub fn diff_summaries(
    scope: &Value,
    workspace_path: &str,
    target_files: &[String],
) -> Result<Vec<FileSummary>, String> {
    let target_set: BTreeSet<&str> = target_files.iter().map(String::as_str).collect();
    let output = run_git(&diff_arguments(scope), workspace_path)?;
    let mut by_file: BTreeMap<String, FileSummary> = BTreeMap::new();

    for line in output.lines() {
        let Some((additions, deletions, candidate_paths)) = parse_numstat_line(line) else {
            continue;
        };
        for file_path in candidate_paths
            .into_iter()
            .filter(|path| target_set.contains(path.as_str()))
        {
            let current = by_file.entry(file_path.clone()).or_insert(FileSummary {
                file_path,
                additions: 0,
                deletions: 0,
            });
            current.additions += additions;
            current.deletions += deletions;
        }
    }

    for file_path in untracked_files(workspace_path, target_files)? {
        if by_file.contains_key(&file_path) {
            continue;
        }
        by_file.insert(
            file_path.clone(),
            FileSummary {
                file_path: file_path.clone(),
                additions: line_count(Path::new(workspace_path).join(file_path).as_path()),
                deletions: 0,
            },
        );
    }

    Ok(target_files
        .iter()
        .filter_map(|file_path| by_file.get(file_path).cloned())
        .collect())
}

fn diff_arguments(scope: &Value) -> Vec<String> {
    let mut args = vec![
        "diff".to_string(),
        "--numstat".to_string(),
        "-M".to_string(),
        "-C".to_string(),
    ];
    match scope
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or_default()
    {
        "staged" => args.push("--cached".to_string()),
        "against_ref" => {
            if let Some(reference) = scope
                .get("ref")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
            {
                args.push(reference.to_string());
            }
        }
        _ => {}
    }
    args
}

fn parse_numstat_line(raw_line: &str) -> Option<(i32, i32, Vec<String>)> {
    let mut parts = raw_line.split('\t');
    let additions = parts.next()?.parse::<i32>().ok().unwrap_or(0).max(0);
    let deletions = parts.next()?.parse::<i32>().ok().unwrap_or(0).max(0);
    let raw_path = parts.next()?.trim();
    let candidate_paths = rename_aware_paths(raw_path);
    if candidate_paths.is_empty() {
        return None;
    }
    Some((additions, deletions, candidate_paths))
}

fn rename_aware_paths(raw_path: &str) -> Vec<String> {
    let trimmed = raw_path.trim();
    if trimmed.is_empty() {
        return Vec::new();
    }

    let mut candidates = BTreeSet::from([trimmed.to_string()]);
    if let Some(expanded) = expanded_brace_paths(trimmed) {
        candidates.extend(expanded);
    } else if let Some((from, to)) = trimmed.split_once(" => ") {
        candidates.insert(from.trim().to_string());
        candidates.insert(to.trim().to_string());
    }
    candidates
        .into_iter()
        .filter(|item| !item.is_empty())
        .collect()
}

fn expanded_brace_paths(raw_path: &str) -> Option<[String; 2]> {
    let open = raw_path.find('{')?;
    let close = raw_path[open..].find('}')? + open;
    let body = &raw_path[open + 1..close];
    let (from, to) = body.split_once(" => ")?;
    Some([
        format!("{}{}{}", &raw_path[..open], from, &raw_path[close + 1..]),
        format!("{}{}{}", &raw_path[..open], to, &raw_path[close + 1..]),
    ])
}

fn run_git(arguments: &[String], workspace_path: &str) -> Result<String, String> {
    let output = Command::new("/usr/bin/git")
        .args(arguments)
        .current_dir(workspace_path)
        .output()
        .map_err(|err| err.to_string())?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

fn untracked_files(workspace_path: &str, target_files: &[String]) -> Result<Vec<String>, String> {
    if target_files.is_empty() {
        return Ok(Vec::new());
    }
    let mut args = vec![
        "ls-files".to_string(),
        "--others".to_string(),
        "--exclude-standard".to_string(),
        "--".to_string(),
    ];
    args.extend(target_files.iter().cloned());
    Ok(run_git(&args, workspace_path)?
        .lines()
        .map(str::trim)
        .filter(|item| !item.is_empty())
        .map(str::to_string)
        .collect())
}

fn line_count(path: &Path) -> i32 {
    let Ok(text) = fs::read_to_string(path) else {
        return 0;
    };
    if text.is_empty() {
        return 0;
    }
    let count = text.lines().count() as i32;
    if text.ends_with('\n') {
        count
    } else {
        count.max(1)
    }
}
