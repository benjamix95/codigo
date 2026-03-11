use super::models::ReviewTask;
use serde_json::Value;
use std::collections::HashSet;

pub enum TaskExtraction {
    Tasks(Vec<ReviewTask>),
    NoFixes,
    InvalidJson(String),
    NoPayload(String),
}

pub enum ReviewFindingsState {
    Issues,
    Clean,
    Inconclusive(String),
}

pub fn parse_review_tasks(analysis_text: &str, files_to_review: &[String], max_workers: usize) -> TaskExtraction {
    let Some(json) = extract_review_tasks_json(analysis_text) else {
        return TaskExtraction::NoPayload("No JSON review task block found in analysis output.".to_string());
    };
    match parse_tasks_json(&json, files_to_review) {
        Ok(tasks) if tasks.is_empty() => TaskExtraction::NoFixes,
        Ok(tasks) => TaskExtraction::Tasks(tasks.into_iter().take(max_workers).collect()),
        Err(message) => TaskExtraction::InvalidJson(message),
    }
}

fn extract_review_tasks_json(text: &str) -> Option<String> {
    if let Some(start) = text.rfind("```json") {
        let rest = &text[start + 7..];
        if let Some(end) = rest.find("```") {
            let candidate = rest[..end].trim();
            if candidate.starts_with('[') && candidate.ends_with(']') {
                return Some(candidate.to_string());
            }
        }
    }
    let start = text.rfind('[')?;
    let end = text[start..].find(']')?;
    let candidate = text[start..start + end + 1].trim();
    if candidate.starts_with('[') && candidate.ends_with(']') {
        return Some(candidate.to_string());
    }
    None
}

fn parse_tasks_json(json: &str, allowed_files: &[String]) -> Result<Vec<ReviewTask>, String> {
    let parsed: Vec<Value> = serde_json::from_str(json)
        .map_err(|_| "Unable to parse task JSON block as an array.".to_string())?;
    let allowed: HashSet<String> = allowed_files.iter().cloned().collect();
    let mut tasks = Vec::new();
    let mut claimed = HashSet::new();
    let mut used_ids = HashSet::new();
    for (index, value) in parsed.iter().enumerate() {
        let object = match value.as_object() {
            Some(object) => object,
            None => continue,
        };
        let preferred_id = object.get("id").and_then(Value::as_str).unwrap_or("").trim();
        let id = unique_id(preferred_id, index, &mut used_ids);
        let description = object
            .get("description")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or("Fix issues in assigned files")
            .to_string();
        let files = object
            .get("files")
            .and_then(Value::as_array)
            .map(|items| {
                items.iter().filter_map(Value::as_str).map(normalize_file).collect::<Vec<_>>()
            })
            .unwrap_or_default();
        let mut scoped_files = Vec::new();
        for file in files {
            if !allowed.is_empty() && !allowed.contains(&file) {
                continue;
            }
            if claimed.insert(file.clone()) {
                scoped_files.push(file);
            }
        }
        if scoped_files.is_empty() {
            continue;
        }
        tasks.push(ReviewTask {
            id,
            description,
            files: scoped_files,
            severity: object.get("severity").and_then(Value::as_str).unwrap_or("warning").to_string(),
            category: object.get("category").and_then(Value::as_str).map(ToString::to_string),
            line_number: object.get("line").and_then(Value::as_i64).map(|value| value as i32),
            end_line_number: object.get("end_line").and_then(Value::as_i64).map(|value| value as i32),
            origin: object.get("origin").and_then(Value::as_str).unwrap_or("reviewer").to_string(),
            confidence: object.get("confidence").and_then(Value::as_f64),
            evidence: object.get("evidence").and_then(Value::as_str).map(ToString::to_string),
            expected_invariant: object.get("expected_invariant").and_then(Value::as_str).map(ToString::to_string),
            repro_or_reasoning: object.get("repro_or_reasoning").and_then(Value::as_str).map(ToString::to_string),
            source_tool: object.get("source_tool").and_then(Value::as_str).map(ToString::to_string),
            blocking: object.get("blocking").and_then(Value::as_bool),
        });
    }
    Ok(tasks)
}

pub fn classify_review_outcome(text: &str) -> ReviewFindingsState {
    let lower = text.to_lowercase();
    let clean_indicators = [
        "no issues found",
        "no remaining issues",
        "everything looks good",
        "code looks good",
        "no critical issues",
    ];
    let issue_indicators = [
        "security vulnerability",
        "security risk",
        "regression",
        "race condition",
        "deadlock",
        "memory leak",
        "issue",
        "warning",
        "error",
        "critical",
    ];
    if issue_indicators.iter().any(|item| lower.contains(item)) && !clean_indicators.iter().any(|item| lower.contains(item))
    {
        return ReviewFindingsState::Issues;
    }
    if clean_indicators.iter().any(|item| lower.contains(item)) {
        return ReviewFindingsState::Clean;
    }
    ReviewFindingsState::Inconclusive("No robust issue indicators found in re-review output.".to_string())
}

fn normalize_file(raw: &str) -> String {
    raw.trim().trim_start_matches("./").to_string()
}

fn unique_id(preferred: &str, index: usize, used: &mut HashSet<String>) -> String {
    let base = if preferred.is_empty() {
        format!("review-{index}")
    } else {
        preferred.to_string()
    };
    if used.insert(base.clone()) {
        return base;
    }
    let mut counter = 1;
    loop {
        let candidate = format!("{base}-{counter}");
        if used.insert(candidate.clone()) {
            return candidate;
        }
        counter += 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_last_json_code_block_and_limits_workers() {
        let text = "analysis\n```json\n[{\"id\":\"one\",\"description\":\"a\",\"files\":[\"A.swift\"]}]\n```\n```json\n[{\"id\":\"two\",\"description\":\"b\",\"files\":[\"B.swift\"]}]\n```";
        match parse_review_tasks(text, &["B.swift".to_string()], 1) {
            TaskExtraction::Tasks(tasks) => {
                assert_eq!(tasks.len(), 1);
                assert_eq!(tasks[0].id, "two");
            }
            _ => panic!("expected tasks"),
        }
    }

    #[test]
    fn classifies_clean_and_issue_text() {
        assert!(matches!(
            classify_review_outcome("No issues found. Everything looks good."),
            ReviewFindingsState::Clean
        ));
        assert!(matches!(
            classify_review_outcome("A security vulnerability remains in auth flow."),
            ReviewFindingsState::Issues
        ));
    }
}
