use regex::Regex;
use std::sync::OnceLock;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PlanOptionRecord {
    pub title: String,
    pub full_text: String,
    pub todos: Vec<String>,
}

pub fn parse_plan_screening_decision(text: &str) -> &'static str {
    let normalized = text.trim().to_uppercase();
    if normalized.ends_with("NO_PLAN_NEEDED") {
        "no_plan_needed"
    } else if normalized.ends_with("PLAN_NEEDED") {
        "plan_needed"
    } else {
        "unknown"
    }
}

pub fn plan_screening_status_message(decision: &str) -> String {
    match decision {
        "no_plan_needed" => "Request looks straightforward. Continuing...".to_string(),
        _ => "Starting codebase analysis...".to_string(),
    }
}

pub fn should_ask_plan_clarifications(analysis_text: &str, user_request: &str) -> bool {
    let normalized = format!("{analysis_text}\n{user_request}").to_lowercase();
    [
        "blocked",
        "cannot proceed",
        "can't proceed",
        "ambiguous",
        "unclear",
        "missing requirement",
        "need clarification",
        "requires clarification",
    ]
    .iter()
    .any(|pattern| normalized.contains(pattern))
}

pub fn should_allow_follow_up_clarification(user_request: &str, clarification_cycles: i32) -> bool {
    clarification_cycles < 2
        && ["ask", "chiedi", "clarification"]
            .iter()
            .any(|pattern| user_request.to_lowercase().contains(pattern))
}

pub fn extract_clarification_payload(text: &str) -> Option<String> {
    let lower = text.to_lowercase();
    if lower.contains("## questions")
        || lower.contains("clarification questions")
        || lower.contains("clarifications needed")
    {
        Some(text.trim().to_string())
    } else {
        None
    }
}

pub fn has_no_questions_needed_signal(text: &str) -> bool {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return false;
    }

    let without_fences = fenced_line_regex().replace_all(trimmed, " ");
    let candidate = without_fences
        .lines()
        .take(6)
        .collect::<Vec<_>>()
        .join(" ")
        .trim()
        .to_lowercase();

    no_questions_regex().is_match(&candidate)
}

pub fn clarifications_needed_section(text: &str) -> Option<String> {
    let normalized = text.trim();
    if normalized.is_empty() {
        return None;
    }
    let captures = clarifications_needed_regex().find(normalized)?;
    let section = normalized[captures.start()..].trim();
    (!section.is_empty()).then(|| section.to_string())
}

pub fn parse_plan_option_records(text: &str) -> Vec<PlanOptionRecord> {
    let normalized = text.trim();
    if normalized.is_empty() {
        return Vec::new();
    }

    let mut matches = option_header_regex()
        .captures_iter(normalized)
        .filter_map(|capture| {
            let header = capture.get(0)?;
            let title = capture
                .get(1)
                .map(|value| value.as_str().trim().to_string())
                .filter(|value| !value.is_empty())
                .unwrap_or_else(|| "Plan".to_string());
            Some((header.start(), header.end(), title))
        })
        .collect::<Vec<_>>();

    if matches.is_empty() {
        let todos = extract_todos_from_option_text(normalized);
        if has_required_todo_header(normalized) && !todos.is_empty() {
            return vec![PlanOptionRecord {
                title: extract_display_summary_title(normalized)
                    .unwrap_or_else(|| "Plan".to_string()),
                full_text: normalized.to_string(),
                todos,
            }];
        }
        return Vec::new();
    }

    matches.sort_by_key(|item| item.0);
    let mut records = Vec::new();
    for (index, (start, _, title)) in matches.iter().enumerate() {
        let end = matches
            .get(index + 1)
            .map(|item| item.0)
            .unwrap_or_else(|| normalized.len());
        let slice = normalized[*start..end].trim();
        if slice.is_empty() {
            continue;
        }
        records.push(PlanOptionRecord {
            title: title.clone(),
            full_text: slice.to_string(),
            todos: extract_todos_from_option_text(slice),
        });
    }
    records
}

pub fn todo_compliant_options(text: &str) -> Vec<PlanOptionRecord> {
    parse_plan_option_records(text)
        .into_iter()
        .filter(|item| has_required_todo_header(&item.full_text) && !item.todos.is_empty())
        .collect()
}

pub fn has_required_todo_header(text: &str) -> bool {
    todo_header_regex().is_match(text)
}

pub fn extract_todos_from_option_text(text: &str) -> Vec<String> {
    let normalized = text.trim();
    if normalized.is_empty() {
        return Vec::new();
    }

    let Some(todo_header) = todo_header_regex().find(normalized) else {
        return Vec::new();
    };
    let tail = &normalized[todo_header.end()..];
    let section = next_header_regex()
        .find(tail)
        .map(|header| &tail[..header.start()])
        .unwrap_or(tail);

    let mut todos = Vec::new();
    for raw_line in section.lines() {
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }

        let candidate = checklist_regex()
            .captures(line)
            .and_then(|capture| capture.get(1).map(|value| value.as_str()))
            .or_else(|| {
                numbered_regex()
                    .captures(line)
                    .and_then(|capture| capture.get(1).map(|value| value.as_str()))
            })
            .or_else(|| {
                bullet_regex()
                    .captures(line)
                    .and_then(|capture| capture.get(1).map(|value| value.as_str()))
            });

        if let Some(candidate) = candidate {
            let cleaned = cleanup_markdown_inline(candidate);
            if !cleaned.is_empty() {
                todos.push(cleaned);
            }
        }
    }

    todos
}

pub fn extract_display_summary_title(text: &str) -> Option<String> {
    let normalized = text.trim();
    if normalized.is_empty() {
        return None;
    }

    for line in normalized.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if let Some(capture) = option_header_regex().captures(trimmed) {
            if let Some(title) = capture.get(1) {
                let value = cleanup_markdown_inline(title.as_str());
                if !value.is_empty() {
                    return Some(value);
                }
            }
        }
        if let Some(header) = markdown_header_regex().captures(trimmed) {
            if let Some(value) = header.get(1) {
                let cleaned = cleanup_markdown_inline(value.as_str());
                if !cleaned.is_empty() {
                    return Some(cleaned);
                }
            }
        }
    }

    Some(
        normalized
            .lines()
            .find(|line| !line.trim().is_empty())
            .map(cleanup_markdown_inline)
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "Plan".to_string()),
    )
}

fn cleanup_markdown_inline(raw: &str) -> String {
    raw.replace('`', "")
        .replace("**", "")
        .replace('*', "")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .trim()
        .trim_matches('-')
        .trim()
        .to_string()
}

fn option_header_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(
            r"(?im)^\s*(?:#{1,3}\s*)?(?:Option|Approach|Plan)(?:\s+(?:\d+|[A-Z]))?\s*[:\-\u{2013}\u{2014}]\s*(.+?)\s*$",
        )
        .expect("valid option header regex")
    })
}

fn todo_header_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(
            r"(?im)^\s*(?:#{1,6}\s*)?(?:todo|to-do|tasks?|implementation\s+steps?|execution\s+steps?|next\s+steps?|checklist|action\s+items?|work\s*plan)\b:?\s*$",
        )
        .expect("valid todo header regex")
    })
}

fn next_header_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(r"(?im)^\s*#{1,6}\s+\S").expect("valid next header regex")
    })
}

fn checklist_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(r"(?i)^\s*[-*•]\s*\[\s*[x ]?\s*\]\s*(.+?)\s*$").expect("valid checklist regex")
    })
}

fn numbered_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"^\s*\d+[.)]\s+(.+?)\s*$").expect("valid numbered regex"))
}

fn bullet_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"^\s*[-*•]\s+(.+?)\s*$").expect("valid bullet regex"))
}

fn markdown_header_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(r"(?i)^\s*#{1,6}\s*(?:plan\s*:?\s*)?(.+?)\s*$").expect("valid markdown header regex")
    })
}

fn clarifications_needed_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(r"(?im)^\s*#{1,3}\s*clarifications?\s*needed\s*:?\s*$")
            .expect("valid clarifications needed regex")
    })
}

fn fenced_line_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"(?m)^```[^\n]*$").expect("valid fenced line regex"))
}

fn no_questions_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(r"(?i)\bno[\s_\-]*questions[\s_\-]*needed\b").expect("valid no questions regex")
    })
}

#[cfg(test)]
mod tests {
    use super::{
        extract_display_summary_title, extract_todos_from_option_text, has_no_questions_needed_signal,
        parse_plan_option_records, todo_compliant_options,
    };

    #[test]
    fn parses_strict_plan_options_and_todos() {
        let input = r#"
## Option 1: Refactor parser
## Todo
- [ ] Extract helper
- [ ] Add tests

## Option 2: Harden pipeline
## Todo
1. Add regression
2. Run cargo test
"#;

        let records = todo_compliant_options(input);
        assert_eq!(records.len(), 2);
        assert_eq!(records[0].title, "Refactor parser");
        assert_eq!(records[0].todos, vec!["Extract helper", "Add tests"]);
        assert_eq!(records[1].todos, vec!["Add regression", "Run cargo test"]);
    }

    #[test]
    fn treats_single_plan_with_todo_as_option_record() {
        let input = r#"
## Plan: Ship Rust Cutover
## Todo
- [ ] Move parser
- [ ] Run tests
"#;
        let records = parse_plan_option_records(input);
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].title, "Ship Rust Cutover");
        assert_eq!(records[0].todos, vec!["Move parser", "Run tests"]);
    }

    #[test]
    fn detects_no_questions_needed_variants() {
        assert!(has_no_questions_needed_signal("NO_QUESTIONS_NEEDED"));
        assert!(has_no_questions_needed_signal("## Decision\nNo-Questions-Needed"));
        assert!(!has_no_questions_needed_signal("need more clarification"));
    }

    #[test]
    fn extracts_summary_title_from_option_or_header() {
        assert_eq!(
            extract_display_summary_title("## Option 1: Parser hardening"),
            Some("Parser hardening".to_string())
        );
        assert_eq!(
            extract_display_summary_title("## Plan: Ship parser migration"),
            Some("Ship parser migration".to_string())
        );
    }

    #[test]
    fn extracts_todos_until_next_header() {
        let input = r#"
## Todo
- [ ] First
- [ ] Second
## Mermaid
```mermaid
graph TD
```
"#;
        assert_eq!(extract_todos_from_option_text(input), vec!["First", "Second"]);
    }
}
