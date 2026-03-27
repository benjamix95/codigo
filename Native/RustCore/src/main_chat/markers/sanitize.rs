use super::patterns;
const COMMON_NEEDLES: &[&str] = &[
    "[CODERIDE",
    "markers:",
    "todo_write|",
    "todo_read|",
    "plan_step",
    "plan_create",
    "plan_read",
    "plan_step_upsert",
    "plan_step_batch_update",
    "plan_step_reorder",
    "plan_step_dependency_set",
    "plan_set_walkthrough",
    "plan_history_read",
    "plan_diff",
    "plan_request_user_input",
    "read_batch",
    "web_search",
    "web_fetch",
    "instant_grep",
    "coderide_show_task_panel",
    "coderide_show_swarm_panel",
];

const AGGRESSIVE_NEEDLES: &[&str] = &[
    "IDE: files=",
    "Planning bug review workflow",
    "Planning code review workflow",
    "Explored ",
    "Inspecting ",
    "Ran ",
    "Bootstrapping ",
    "Initializing ",
    "Preparing ",
    "Setting ",
    "Starting ",
];

const STRUCTURED_KEYS: &[&str] = &[
    "id", "title", "status", "priority", "notes", "files", "step_id", "queryid", "query",
    "group_id", "count", "task",
];

pub fn strip_coderide_markers(content: &str, aggressive: bool) -> String {
    let content = strip_lines_starting_with_coderide_tool_noise(content);
    if !should_run_marker_cleanup(&content, aggressive) {
        return normalize_fast_path(&content, aggressive);
    }

    let mut result = split_by_code_fences(&content)
        .into_iter()
        .map(|(text, is_code_fence)| {
            if is_code_fence {
                text
            } else {
                strip_prose_segment(&text, aggressive)
            }
        })
        .collect::<String>();

    result = patterns::excessive_newlines()
        .replace_all(&result, "\n\n")
        .into_owned();
    if aggressive {
        result.trim().to_string()
    } else {
        result
    }
}

fn should_run_marker_cleanup(content: &str, aggressive: bool) -> bool {
    if content.is_empty() {
        return false;
    }
    if COMMON_NEEDLES
        .iter()
        .any(|needle| content.to_lowercase().contains(&needle.to_lowercase()))
    {
        return true;
    }
    aggressive
        && (content.contains('=') && content.contains('|')
            || AGGRESSIVE_NEEDLES
                .iter()
                .any(|needle| content.to_lowercase().contains(&needle.to_lowercase())))
}

fn line_should_be_hidden_as_coderide_tool_noise(line: &str) -> bool {
    let trimmed = line.trim_start();
    if trimmed.is_empty() {
        return false;
    }
    let payload = if let Some(rest) = trimmed.strip_prefix("- ") {
        rest
    } else if let Some(rest) = trimmed.strip_prefix("* ") {
        rest
    } else if let Some(rest) = trimmed.strip_prefix("+ ") {
        rest
    } else {
        trimmed
    };
    let core = payload.trim_start();
    if core.is_empty() {
        return false;
    }
    let lower = core.to_lowercase();
    if lower.contains("[policy error]") {
        return true;
    }
    lower.starts_with("coderide_")
        || lower.starts_with("mcp__coderide__coderide_")
        || lower.starts_with("functions.mcp__coderide__coderide_")
        || lower.starts_with("functions.coderide_")
}

/// Rimuove righe “rumore” solo-nome-tool (es. `coderide_subagent_explorer`) dalla prose in chat;
/// i blocchi ```…``` restano intatti.
fn strip_lines_starting_with_coderide_tool_noise(content: &str) -> String {
    split_by_code_fences(content)
        .into_iter()
        .map(|(segment, is_code)| {
            if is_code {
                segment
            } else {
                segment
                    .lines()
                    .filter(|line| !line_should_be_hidden_as_coderide_tool_noise(line))
                    .collect::<Vec<_>>()
                    .join("\n")
            }
        })
        .collect()
}

fn normalize_fast_path(content: &str, aggressive: bool) -> String {
    let mut result = if aggressive {
        content.trim().to_string()
    } else {
        content.to_string()
    };
    while result.contains("\n\n\n") {
        result = result.replace("\n\n\n", "\n\n");
    }
    result
}

fn split_by_code_fences(input: &str) -> Vec<(String, bool)> {
    let mut segments = Vec::new();
    let mut cursor = 0usize;
    while let Some(start) = input[cursor..].find("```") {
        let start = cursor + start;
        if start > cursor {
            segments.push((input[cursor..start].to_string(), false));
        }
        if let Some(end_rel) = input[start + 3..].find("```") {
            let end = start + 3 + end_rel + 3;
            segments.push((input[start..end].to_string(), true));
            cursor = end;
        } else {
            segments.push((input[start..].to_string(), true));
            return segments;
        }
    }
    if cursor < input.len() {
        segments.push((input[cursor..].to_string(), false));
    }
    segments
}

fn strip_prose_segment(text: &str, aggressive: bool) -> String {
    let mut out = patterns::coderide_marker()
        .replace_all(text, "")
        .into_owned();
    out = patterns::policy_error_run()
        .replace_all(&out, "")
        .into_owned();
    out = remove_incomplete_markers(out);
    if aggressive {
        out = patterns::inline_op_prefix()
            .replace_all(&out, "")
            .into_owned();
        out = filter_aggressive_lines(out);
    }
    out = patterns::inline_marker_prefix()
        .replace_all(&out, "")
        .into_owned();
    out = patterns::inline_marker_types()
        .replace_all(&out, "")
        .into_owned();
    out = patterns::inline_marker_broken()
        .replace_all(&out, "")
        .into_owned();
    out = patterns::technical_events()
        .replace_all(&out, "")
        .into_owned();
    if aggressive {
        out = patterns::sticky_key_value()
            .replace_all(&out, "$1 $2")
            .into_owned();
        out = patterns::single_key_value()
            .replace_all(&out, "")
            .into_owned();
        out = patterns::key_value_bracket()
            .replace_all(&out, "")
            .into_owned();
        out = strip_structured_payloads(out);
    }
    out = patterns::trailing_space_newline()
        .replace_all(&out, "\n")
        .into_owned();
    out = patterns::excessive_spaces()
        .replace_all(&out, " ")
        .into_owned();
    patterns::missing_space_after_punct()
        .replace_all(&out, "$1 $2")
        .into_owned()
}

fn remove_incomplete_markers(mut out: String) -> String {
    while let Some(start) = out.to_lowercase().find("[coderide") {
        let tail = &out[start..];
        if let Some(end) = tail.find(']') {
            out.replace_range(start..start + end + 1, "");
        } else if let Some(newline) = tail.find('\n') {
            out.replace_range(start..start + newline, "");
        } else {
            out.replace_range(start..out.len(), "");
            break;
        }
    }
    out
}

fn filter_aggressive_lines(text: String) -> String {
    text.lines()
        .filter(|line| !should_drop_aggressive_line(line.trim()))
        .collect::<Vec<_>>()
        .join("\n")
}

fn should_drop_aggressive_line(line: &str) -> bool {
    if line.is_empty() {
        return false;
    }
    let lower = line.to_lowercase();
    if lower.contains("ide: files=") {
        return true;
    }
    if lower == "planning bug review workflow" || lower == "planning code review workflow" {
        return true;
    }
    if lower.starts_with("explored ")
        || lower.starts_with("inspecting ")
        || lower.starts_with("ran ")
    {
        return true;
    }
    false
}

fn strip_structured_payloads(mut input: String) -> String {
    loop {
        let matches = patterns::structured_payload()
            .find_iter(&input)
            .map(|m| (m.start(), m.end(), m.as_str().to_string()))
            .collect::<Vec<_>>();
        if matches.is_empty() {
            break;
        }
        let mut removed = false;
        for (start, end, chunk) in matches.into_iter().rev() {
            let keys = chunk
                .split('|')
                .filter_map(|segment| segment.split_once('='))
                .map(|(key, _)| key.trim().to_lowercase())
                .collect::<Vec<_>>();
            let marker_count = keys
                .iter()
                .filter(|key| STRUCTURED_KEYS.contains(&key.as_str()))
                .count();
            if marker_count >= 3 {
                input.replace_range(start..end, "");
                removed = true;
            }
        }
        if !removed {
            break;
        }
    }

    input
        .lines()
        .filter(|line| {
            let marker_count = line
                .split('|')
                .filter_map(|segment| segment.split_once('='))
                .map(|(key, _)| key.trim().to_lowercase())
                .filter(|key| STRUCTURED_KEYS.contains(&key.as_str()))
                .count();
            marker_count < 3
        })
        .collect::<Vec<_>>()
        .join("\n")
}
