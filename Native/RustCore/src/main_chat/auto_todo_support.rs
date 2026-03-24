use app_core_protocol::main_chat_ui::MainChatUiIntentRequest;

pub const AUTO_TODO_GENERIC_FALLBACK_TITLE: &str = "Complete the required operational steps";

pub fn auto_todo_runtime_notes(operation_count: i32) -> String {
    match operation_count {
        i32::MIN..=0 => "Auto-generated: execution started before an explicit todo was created.".to_string(),
        1 => "Auto-generated: tracking live operational activity until the agent publishes an explicit todo.".to_string(),
        _ => format!(
            "Auto-generated: tracking {} operational steps until the agent publishes an explicit todo.",
            operation_count
        ),
    }
}

pub fn preferred_title(current_title: &str, candidate_title: &str) -> String {
    let current = current_title.trim();
    let candidate = candidate_title.trim();
    if candidate.is_empty() {
        return current.to_string();
    }
    if current.is_empty()
        || (current == AUTO_TODO_GENERIC_FALLBACK_TITLE
            && candidate != AUTO_TODO_GENERIC_FALLBACK_TITLE)
    {
        return candidate.to_string();
    }
    current.to_string()
}

pub fn preferred_active_form(
    current_active_form: &str,
    immediate_label: String,
    title: &str,
) -> String {
    let current = current_active_form.trim();
    let immediate = immediate_label.trim();
    let fallback = title.trim();
    if !immediate.is_empty() {
        immediate.to_string()
    } else if !current.is_empty() {
        current.to_string()
    } else {
        fallback.to_string()
    }
}

pub fn auto_todo_title(request: &MainChatUiIntentRequest) -> String {
    let activity_title = payload(request, "activity_title");
    if !activity_title.is_empty() && !is_placeholder_title(&activity_title) {
        return activity_title;
    }
    if let Some(path) = first_non_empty(&[request.payload.get("path"), request.payload.get("file")])
    {
        return format!(
            "Complete changes on {}",
            path.rsplit('/').next().unwrap_or(path)
        );
    }
    if let Some(query) = first_non_empty(&[request.payload.get("query")]) {
        return format!("Complete analysis: {}", truncate(query, 80));
    }
    if let Some(command) = first_non_empty(&[request.payload.get("command")]) {
        return format!("Complete execution: {}", truncate(command, 80));
    }
    AUTO_TODO_GENERIC_FALLBACK_TITLE.to_string()
}

pub fn linked_files_from_request(request: &MainChatUiIntentRequest) -> Vec<String> {
    let mut files = Vec::new();
    for key in ["path", "file", "files"] {
        if let Some(raw) = request.payload.get(key) {
            for item in raw
                .split(',')
                .map(|value| value.trim())
                .filter(|value| !value.is_empty())
            {
                if !files.iter().any(|candidate| candidate == item) {
                    files.push(item.to_string());
                }
            }
        }
    }
    files.sort();
    files
}

pub fn merged_linked_files(existing: &[String], incoming: &[String]) -> Vec<String> {
    let mut merged = existing.to_vec();
    for item in incoming {
        if !merged.iter().any(|candidate| candidate == item) {
            merged.push(item.clone());
        }
    }
    merged.sort();
    merged
}

pub fn payload(request: &MainChatUiIntentRequest, key: &str) -> String {
    request
        .payload
        .get(key)
        .map(|value| value.trim().to_string())
        .unwrap_or_default()
}

fn is_placeholder_title(raw_title: &str) -> bool {
    let normalized = raw_title.trim().to_lowercase();
    if normalized.is_empty() {
        return true;
    }
    matches!(
        normalized.as_str(),
        "task"
            | "tasks"
            | "todo"
            | "todos"
            | "step"
            | "steps"
            | "analysis"
            | "workflow"
            | "execution"
            | "plan"
    ) || normalized.contains("task panel")
        || normalized.contains("todo update")
        || normalized.contains("turn started")
        || normalized.starts_with("task ")
        || normalized.starts_with("step ")
}

fn first_non_empty<'a>(values: &[Option<&'a String>]) -> Option<&'a str> {
    values
        .iter()
        .flatten()
        .map(|value| value.trim())
        .find(|value| !value.is_empty())
}

fn truncate(value: &str, limit: usize) -> String {
    value.chars().take(limit).collect()
}
