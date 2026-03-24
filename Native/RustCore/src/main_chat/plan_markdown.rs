use app_core_protocol::main_chat_runtime::{
    MainChatPlanQuestion, MainChatPlanQuestionOption, MainChatPlanQuestionnaire,
};
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

pub fn parse_clarification_questionnaire(text: &str) -> Option<MainChatPlanQuestionnaire> {
    let normalized = text.trim();
    if normalized.is_empty() || !clarification_header_regex().is_match(normalized) {
        return None;
    }

    let mut in_block = false;
    let mut questions = Vec::new();
    let mut current_id: Option<i32> = None;
    let mut current_prompt = String::new();
    let mut current_options: Vec<MainChatPlanQuestionOption> = Vec::new();
    let mut current_has_checkbox_options = false;
    let mut invalid_block = false;

    let flush_question = |questions: &mut Vec<MainChatPlanQuestion>,
                          current_id: &mut Option<i32>,
                          current_prompt: &mut String,
                          current_options: &mut Vec<MainChatPlanQuestionOption>,
                          current_has_checkbox_options: &mut bool,
                          invalid_block: &mut bool| {
        let Some(question_id) = *current_id else {
            return;
        };
        let prompt = current_prompt.trim().to_string();
        if prompt.is_empty() || current_options.len() < 2 {
            *invalid_block = true;
            return;
        }
        let has_text_marker = multi_select_marker_regex().is_match(&prompt);
        let cleaned_prompt = if has_text_marker {
            multi_select_marker_regex()
                .replace_all(&prompt, "")
                .split_whitespace()
                .collect::<Vec<_>>()
                .join(" ")
                .trim()
                .to_string()
        } else {
            prompt
        };
        questions.push(MainChatPlanQuestion {
            id: question_id,
            prompt: cleaned_prompt,
            options: current_options.clone(),
            is_multi_select: has_text_marker || *current_has_checkbox_options,
        });
        *current_id = None;
        current_prompt.clear();
        current_options.clear();
        *current_has_checkbox_options = false;
    };

    for raw_line in normalized.lines() {
        let trimmed = raw_line.trim();
        if clarification_header_regex().is_match(trimmed) {
            in_block = true;
            continue;
        }
        if !in_block {
            continue;
        }
        if trimmed.starts_with('#') {
            break;
        }
        if trimmed.is_empty() {
            continue;
        }

        let looks_like_numeric_option_line =
            current_id.is_some() && numeric_option_line_regex().is_match(trimmed);
        if !looks_like_numeric_option_line {
            if let Some(capture) = question_line_regex().captures(trimmed) {
                flush_question(
                    &mut questions,
                    &mut current_id,
                    &mut current_prompt,
                    &mut current_options,
                    &mut current_has_checkbox_options,
                    &mut invalid_block,
                );
                if invalid_block {
                    return if questions.is_empty() {
                        None
                    } else {
                        Some(MainChatPlanQuestionnaire { questions })
                    };
                }
                current_id = capture
                    .get(1)
                    .and_then(|value| value.as_str().parse::<i32>().ok());
                current_prompt = capture
                    .get(2)
                    .map(|value| value.as_str().trim().to_string())
                    .unwrap_or_default();
                continue;
            }
        }

        if current_id.is_none() {
            return None;
        }

        if let Some(option) = parse_question_option(trimmed, &current_options) {
            if checkbox_option_regex().is_match(trimmed) {
                current_has_checkbox_options = true;
            }
            current_options.push(option);
            continue;
        }

        if current_options.is_empty() {
            current_prompt = format!("{} {}", current_prompt, trimmed).trim().to_string();
        } else if let Some(last) = current_options.last_mut() {
            last.text = format!("{} {}", last.text, trimmed).trim().to_string();
        }
    }

    flush_question(
        &mut questions,
        &mut current_id,
        &mut current_prompt,
        &mut current_options,
        &mut current_has_checkbox_options,
        &mut invalid_block,
    );
    if invalid_block && questions.is_empty() {
        return None;
    }
    (!questions.is_empty()).then_some(MainChatPlanQuestionnaire { questions })
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

fn parse_question_option(
    line: &str,
    existing: &[MainChatPlanQuestionOption],
) -> Option<MainChatPlanQuestionOption> {
    let (raw_id, raw_text) = if let Some(capture) = alpha_option_regex().captures(line) {
        (
            capture.get(1).map(|value| value.as_str().to_string()),
            capture.get(2).map(|value| value.as_str().to_string()),
        )
    } else if let Some(capture) = numeric_option_regex().captures(line) {
        (
            capture.get(1).map(|value| value.as_str().to_string()),
            capture.get(2).map(|value| value.as_str().to_string()),
        )
    } else if let Some(capture) = bullet_option_regex().captures(line) {
        (None, capture.get(1).map(|value| value.as_str().to_string()))
    } else {
        return None;
    };

    let mut text = raw_text?.trim().to_string();
    if text.is_empty() {
        return None;
    }

    let is_recommended = recommended_suffix_regex().is_match(&text);
    if is_recommended {
        text = recommended_suffix_regex()
            .replace_all(&text, "")
            .trim()
            .to_string();
    }

    Some(MainChatPlanQuestionOption {
        id: normalized_option_id(raw_id.as_deref(), existing),
        text,
        is_recommended,
    })
}

fn normalized_option_id(raw_id: Option<&str>, existing: &[MainChatPlanQuestionOption]) -> String {
    if let Some(raw_id) = raw_id {
        let candidate = raw_id.trim();
        if !candidate.is_empty() {
            let normalized = candidate.to_uppercase();
            if !existing
                .iter()
                .any(|option| option.id.eq_ignore_ascii_case(&normalized))
            {
                return normalized;
            }
        }
    }

    let used = existing
        .iter()
        .map(|option| option.id.to_uppercase())
        .collect::<Vec<_>>();
    for letter in 'A'..='Z' {
        let candidate = letter.to_string();
        if !used.iter().any(|value| value == &candidate) {
            return candidate;
        }
    }
    (existing.len() + 1).to_string()
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
    REGEX.get_or_init(|| Regex::new(r"(?im)^\s*#{1,6}\s+\S").expect("valid next header regex"))
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
        Regex::new(r"(?i)^\s*#{1,6}\s*(?:plan\s*:?\s*)?(.+?)\s*$")
            .expect("valid markdown header regex")
    })
}

fn clarifications_needed_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(r"(?im)^\s*#{1,3}\s*clarifications?\s*needed\s*:?\s*$")
            .expect("valid clarifications needed regex")
    })
}

fn clarification_header_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(
            r"(?im)^\s*#{1,3}\s*(?:clarification\s*questions|questions\s*to\s*clarify|questions|clarifications?\s*needed|need(?:ed)?\s*clarifications?)\s*:?\s*$",
        )
        .expect("valid clarification header regex")
    })
}

fn question_line_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"^\s*(\d+)[.)]\s*(.+)$").expect("valid question line regex"))
}

fn alpha_option_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(r"^\s*(?:[-*•]\s*)?(?:\[\s*[xX ]?\s*\]\s*)?([A-Za-z])[.)]\s+(.+)$")
            .expect("valid alpha option regex")
    })
}

fn numeric_option_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(r"^\s*(?:[-*•]\s*)?(?:\[\s*[xX ]?\s*\]\s*)?(\d{1,2})\)\s+(.+)$")
            .expect("valid numeric option regex")
    })
}

fn bullet_option_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(r"^\s*[-*•]\s*(?:\[\s*[xX ]?\s*\]\s*)?(.+)$").expect("valid bullet option regex")
    })
}

fn checkbox_option_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"^\s*[-*•]\s*\[\s*[xX ]?\s*\]").expect("valid checkbox regex"))
}

fn multi_select_marker_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(
            r"(?i)(?:\(\s*)?(?:select\s+all\s+that\s+apply|select\s+multiple(?:\s+options)?|multi[-\s]?select|seleziona\s+(?:tutto(?:\s+quello\s+che\s+si\s+applica)?|multiplo|multiple|piu)(?:\s+opzioni)?)\s*(?:\))?",
        )
        .expect("valid multi select regex")
    })
}

fn recommended_suffix_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(r"(?i)\s*\((recommended|consigliato|consigliata)\)\s*$")
            .expect("valid recommended suffix regex")
    })
}

fn numeric_option_line_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"^\s*\d+\)\s+\S+").expect("valid numeric option line regex"))
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
        extract_display_summary_title, extract_todos_from_option_text,
        has_no_questions_needed_signal, parse_clarification_questionnaire,
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
        assert!(has_no_questions_needed_signal(
            "## Decision\nNo-Questions-Needed"
        ));
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
        assert_eq!(
            extract_todos_from_option_text(input),
            vec!["First", "Second"]
        );
    }

    #[test]
    fn parses_structured_clarification_questionnaire() {
        let input = r#"
## Questions
1. Quale modulo deve avere priorita'? (select multiple)
A) Parser (Recommended)
B) UI
- [ ] C) Altro
"#;

        let questionnaire = parse_clarification_questionnaire(input).expect("questionnaire");
        assert_eq!(questionnaire.questions.len(), 1);
        assert!(questionnaire.questions[0].is_multi_select);
        assert_eq!(questionnaire.questions[0].options.len(), 3);
        assert!(questionnaire.questions[0].options[0].is_recommended);
    }
}
