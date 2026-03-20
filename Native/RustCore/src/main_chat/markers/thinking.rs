pub fn extract_last_operational_thinking_line(content: &str) -> Option<String> {
    let trimmed = content.trim();
    if trimmed.is_empty() {
        return None;
    }

    let prefixes = [
        "planning", "explored", "inspecting", "ran ", "reading", "analyzing",
        "implementing", "updating", "creating", "generating", "processing",
        "setting", "preparing", "starting", "initializing", "bootstrapping",
        "writing", "searching",
    ];

    trimmed
        .lines()
        .rev()
        .map(str::trim)
        .find(|line| {
            !line.is_empty()
                && line.chars().count() > 3
                && line.chars().count() < 150
                && prefixes
                    .iter()
                    .any(|prefix| line.to_lowercase().starts_with(prefix))
        })
        .map(ToOwned::to_owned)
}
