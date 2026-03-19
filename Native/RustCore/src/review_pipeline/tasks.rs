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
    let Some(json) = extract_review_tasks_json_payload(analysis_text) else {
        return TaskExtraction::NoPayload("No JSON review task block found in analysis output.".to_string());
    };
    match extract_review_tasks_json(analysis_text, files_to_review) {
        Some(ExtractedReviewTasks::JsonTasks(tasks)) if tasks.is_empty() => TaskExtraction::NoFixes,
        Some(ExtractedReviewTasks::JsonTasks(tasks)) => {
            TaskExtraction::Tasks(tasks.into_iter().take(max_workers).collect())
        }
        Some(ExtractedReviewTasks::InvalidJson(message)) => TaskExtraction::InvalidJson(message),
        None => match parse_tasks_json(&json, files_to_review) {
            ParsedTasksResult::Tasks(tasks) if tasks.is_empty() => TaskExtraction::NoFixes,
            ParsedTasksResult::Tasks(tasks) => TaskExtraction::Tasks(tasks.into_iter().take(max_workers).collect()),
            ParsedTasksResult::InvalidJson(message) => TaskExtraction::InvalidJson(message),
        },
    }
}

pub enum ExtractedReviewTasks {
    JsonTasks(Vec<ReviewTask>),
    InvalidJson(String),
}

pub enum ParsedTasksResult {
    Tasks(Vec<ReviewTask>),
    InvalidJson(String),
}

fn extract_review_tasks_json_payload(text: &str) -> Option<String> {
    if let Some(start) = text.rfind("```json") {
        let rest = &text[start + 7..];
        if let Some(end) = rest.find("```") {
            let candidate = rest[..end].trim();
            if candidate.starts_with('[') && candidate.ends_with(']') {
                return Some(candidate.to_string());
            }
        }
    }
    let start = text.find('[')?;
    let end = text.rfind(']')?;
    if end < start {
        return None;
    }
    let candidate = text[start..=end].trim();
    if candidate.starts_with('[') && candidate.ends_with(']') {
        return Some(candidate.to_string());
    }
    None
}

pub fn extract_review_tasks_json(text: &str, allowed_files: &[String]) -> Option<ExtractedReviewTasks> {
    if let Some(start) = text.rfind("```json") {
        let rest = &text[start + 7..];
        if let Some(end) = rest.find("```") {
            let candidate = rest[..end].trim();
            if candidate.starts_with('[') && candidate.ends_with(']') {
                return Some(match parse_tasks_json(candidate, allowed_files) {
                    ParsedTasksResult::Tasks(tasks) => ExtractedReviewTasks::JsonTasks(tasks),
                    ParsedTasksResult::InvalidJson(message) => ExtractedReviewTasks::InvalidJson(message),
                });
            }
        }
    }

    let start = text.find('[')?;
    let end = text.rfind(']')?;
    if end < start {
        return None;
    }
    let candidate = text[start..=end].trim();
    if candidate.starts_with('[') && candidate.ends_with(']') {
        return Some(match parse_tasks_json(candidate, allowed_files) {
            ParsedTasksResult::Tasks(tasks) => ExtractedReviewTasks::JsonTasks(tasks),
            ParsedTasksResult::InvalidJson(message) => ExtractedReviewTasks::InvalidJson(message),
        });
    }
    None
}

pub fn parse_tasks_json(json: &str, allowed_files: &[String]) -> ParsedTasksResult {
    let parsed: Vec<Value> = match serde_json::from_str(json) {
        Ok(parsed) => parsed,
        Err(_) => return ParsedTasksResult::InvalidJson("Unable to parse task JSON block as an array.".to_string()),
    };
    let allowed: HashSet<String> = allowed_files.iter().map(|file| normalize_file(file)).collect();
    let mut tasks = Vec::new();
    let mut claimed = HashSet::new();
    let mut used_ids = HashSet::new();
    let mut invalid_entries = 0;
    for (index, value) in parsed.iter().enumerate() {
        let object = match value.as_object() {
            Some(object) => object,
            None => {
                invalid_entries += 1;
                continue;
            }
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
        let files = deduped_files(
            object
            .get("files")
            .and_then(Value::as_array)
            .map(|items| {
                items.iter().filter_map(Value::as_str).map(normalize_file).collect::<Vec<_>>()
            })
            .unwrap_or_default()
        );
        if files.is_empty() {
            invalid_entries += 1;
            continue;
        }
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
            invalid_entries += 1;
            continue;
        }
        let severity_raw = object.get("severity").and_then(Value::as_str).unwrap_or("warning");
        let severity = match severity_raw.to_lowercase().as_str() {
            "critical" | "warning" | "suggestion" => severity_raw.to_lowercase(),
            _ => "warning".to_string(),
        };
        tasks.push(ReviewTask {
            id,
            description,
            files: scoped_files,
            severity,
            category: object.get("category").and_then(Value::as_str).map(|value| value.trim().to_string()).filter(|value| !value.is_empty()),
            line_number: object.get("line").and_then(Value::as_i64).map(|value| value as i32),
            end_line_number: object.get("end_line").and_then(Value::as_i64).map(|value| value as i32),
            origin: object.get("origin").and_then(Value::as_str).unwrap_or("reviewer").to_string(),
            confidence: object.get("confidence").and_then(Value::as_f64),
            evidence: object.get("evidence").and_then(Value::as_str).map(|value| value.trim().to_string()).filter(|value| !value.is_empty()),
            expected_invariant: object.get("expected_invariant").and_then(Value::as_str).map(|value| value.trim().to_string()).filter(|value| !value.is_empty()),
            repro_or_reasoning: object.get("repro_or_reasoning").and_then(Value::as_str).map(|value| value.trim().to_string()).filter(|value| !value.is_empty()),
            source_tool: object.get("source_tool").and_then(Value::as_str).map(|value| value.trim().to_string()).filter(|value| !value.is_empty()),
            blocking: object.get("blocking").and_then(Value::as_bool),
        });
    }
    if tasks.is_empty() && !parsed.is_empty() {
        return ParsedTasksResult::InvalidJson(if invalid_entries > 0 {
            "All task entries were invalid or outside review scope.".to_string()
        } else {
            "Unable to parse task array entries.".to_string()
        });
    }
    ParsedTasksResult::Tasks(tasks)
}

pub fn classify_review_outcome(text: &str) -> ReviewFindingsState {
    let lower = text.to_lowercase();
    let no_issues_indicators = [
        "no issues found",
        "no issues were found",
        "no significant issues",
        "no problems found",
        "no bugs found",
        "no errors found",
        "no errors detected",
        "no errors",
        "no warnings found",
        "no warnings detected",
        "no warnings",
        "no fix needed",
        "no fixes needed",
        "no fix required",
        "no fixes required",
        "no critical issues",
        "no critical bugs",
        "no critical problems",
        "no critical findings",
        "no security vulnerabilities",
        "no security issues",
        "no security risks",
        "no security concerns",
        "no race conditions",
        "no race condition issues",
        "no memory leaks",
        "no regressions",
        "no regression risks",
        "no crashes",
        "no deadlocks",
        "no injection vulnerabilities",
        "no data loss risks",
        "no infinite loops",
        "code is clean",
        "code looks good",
        "looks good overall",
        "no major issues",
        "all checks pass",
        "all tests pass",
        "no vulnerabilities found",
        "no vulnerabilities detected",
        "lgtm",
        "everything looks good",
        "no actionable issues",
        "no remaining issues",
        "error handling is properly implemented",
        "error handling looks correct",
        "error handling is correct",
        "error handling is adequate",
        "error handling is good",
        "no error handling issues",
    ];
    let has_clean_indicator = no_issues_indicators.iter().any(|item| lower.contains(item));
    let mut sorted_indicators = no_issues_indicators.to_vec();
    sorted_indicators.sort_by_key(|item| std::cmp::Reverse(item.len()));
    let issue_scan_text = sorted_indicators.into_iter().fold(lower.clone(), |partial, phrase| {
        partial.replace(phrase, " ")
    });

    let inconclusive_indicators = [
        "could not determine",
        "unable to assess",
        "insufficient context",
        "need more information",
        "cannot evaluate",
        "unclear",
    ];
    let has_inconclusive_indicator = inconclusive_indicators
        .iter()
        .any(|item| contains_word_or_phrase(&lower, item));

    let strict_issue_indicators = [
        "critical",
        "high severity",
        "security vulnerability",
        "security risk",
        "security issue",
        "regression",
        "crash",
        "null pointer",
        "race condition",
        "memory leak",
        "command injection",
        "sql injection",
        "data loss",
        "deadlock",
        "infinite loop",
        "off-by-one",
        "null dereference",
        "segmentation fault",
        "thread-safety",
        "use-after-free",
        "buffer overflow",
        "integer overflow",
        "integer underflow",
        "path traversal",
        "cross-site scripting",
        "xss",
        "denial of service",
        "type confusion",
        "uninitialized variable",
        "uninitialized memory",
    ];
    let has_strict_issue_indicator = strict_issue_indicators
        .iter()
        .any(|item| issue_scan_text.contains(item));

    let has_word_boundary_issue_indicator = ["leak", "exception", "permission", "authorization", "authentication"]
        .iter()
        .any(|word| contains_word(&issue_scan_text, word));
    let has_weak_word_boundary_issue_indicator = ["bug", "warning", "error", "issue", "severity"]
        .iter()
        .any(|word| contains_word(&issue_scan_text, word));
    let has_fix_action_indicator = [
        "fix required",
        "requires a fix",
        "needs a fix",
        "must be fixed",
        "should be fixed",
        "remaining fix",
    ]
    .iter()
    .any(|phrase| issue_scan_text.contains(phrase));

    if has_strict_issue_indicator
        || has_word_boundary_issue_indicator
        || has_weak_word_boundary_issue_indicator
        || has_fix_action_indicator
    {
        return ReviewFindingsState::Issues;
    }
    if has_clean_indicator {
        return ReviewFindingsState::Clean;
    }
    if has_inconclusive_indicator {
        return ReviewFindingsState::Inconclusive("Review text contained inconclusive language.".to_string());
    }
    ReviewFindingsState::Inconclusive("No robust issue indicators found in re-review output.".to_string())
}

fn normalize_file(raw: &str) -> String {
    raw.trim().trim_start_matches("./").to_string()
}

fn deduped_files(files: Vec<String>) -> Vec<String> {
    let mut out = Vec::new();
    let mut seen = HashSet::new();
    for file in files {
        if !file.is_empty() && seen.insert(file.clone()) {
            out.push(file);
        }
    }
    out
}

fn unique_id(preferred: &str, index: usize, used: &mut HashSet<String>) -> String {
    let normalized_preferred = preferred.trim();
    if !normalized_preferred.is_empty() && used.insert(normalized_preferred.to_string()) {
        return normalized_preferred.to_string();
    }
    let fallback = format!("review-{index}");
    if used.insert(fallback.clone()) {
        return fallback;
    }
    let mut suffix = 1;
    loop {
        let candidate = format!("review-{index}-{suffix}");
        if used.insert(candidate.clone()) {
            return candidate;
        }
        suffix += 1;
    }
}

fn contains_word(text: &str, word: &str) -> bool {
    let bytes = text.as_bytes();
    let word_bytes = word.as_bytes();
    if word_bytes.is_empty() || bytes.len() < word_bytes.len() {
        return false;
    }
    for start in 0..=bytes.len() - word_bytes.len() {
        if &bytes[start..start + word_bytes.len()] != word_bytes {
            continue;
        }
        let left_ok = start == 0 || !is_word_byte(bytes[start - 1]);
        let right_index = start + word_bytes.len();
        let right_ok = right_index == bytes.len() || !is_word_byte(bytes[right_index]);
        if left_ok && right_ok {
            return true;
        }
    }
    false
}

fn contains_word_or_phrase(text: &str, phrase: &str) -> bool {
    if phrase.contains(' ') {
        text.contains(phrase)
    } else {
        contains_word(text, phrase)
    }
}

fn is_word_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || byte == b'_'
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
        assert!(matches!(
            classify_review_outcome("No critical issues in module A, but a security vulnerability remains in auth flow."),
            ReviewFindingsState::Issues
        ));
        assert!(matches!(
            classify_review_outcome("The previous fix was applied correctly and no remaining issues were found."),
            ReviewFindingsState::Clean
        ));
    }

    #[test]
    fn parse_tasks_json_matches_swift_defaults_and_invalid_scope() {
        match parse_tasks_json(r#"[{"files":["x.swift"]}]"#, &[]) {
            ParsedTasksResult::Tasks(tasks) => {
                assert_eq!(tasks[0].id, "review-0");
                assert_eq!(tasks[0].description, "Fix issues in assigned files");
            }
            _ => panic!("expected tasks"),
        }

        assert!(matches!(
            parse_tasks_json(r#"[{"id":"r-0","files":["","  "]}]"#, &[]),
            ParsedTasksResult::InvalidJson(_)
        ));
    }
}
