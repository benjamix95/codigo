use app_core_protocol::app_core::SwiftBoundaryKind;
use std::fs;
use std::path::Path;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AllowlistRule {
    pub kind: SwiftBoundaryKind,
    pub pattern: String,
    pub reason: String,
}

pub fn load_allowlist(path: &Path) -> Result<Vec<AllowlistRule>, String> {
    let contents = fs::read_to_string(path).map_err(|error| {
        format!(
            "Impossibile leggere allowlist Rust cutover {}: {error}",
            path.display()
        )
    })?;
    let mut rules = Vec::new();
    for (index, raw_line) in contents.lines().enumerate() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let parts: Vec<&str> = line.splitn(3, '|').collect();
        if parts.len() != 3 {
            return Err(format!(
                "Allowlist Rust cutover non valida alla riga {}: {}",
                index + 1,
                raw_line
            ));
        }
        let kind = parse_kind(parts[0].trim()).ok_or_else(|| {
            format!(
                "Tipo allowlist Rust cutover sconosciuto alla riga {}: {}",
                index + 1,
                parts[0]
            )
        })?;
        rules.push(AllowlistRule {
            kind,
            pattern: normalize_pattern(parts[1].trim()),
            reason: parts[2].trim().to_string(),
        });
    }
    Ok(rules)
}

pub fn matches(pattern: &str, path: &str) -> bool {
    let normalized_pattern = normalize_pattern(pattern);
    if normalized_pattern == "*" {
        return true;
    }

    let parts: Vec<&str> = normalized_pattern
        .split('*')
        .filter(|part| !part.is_empty())
        .collect();
    if parts.is_empty() {
        return true;
    }

    let starts_anchored = !normalized_pattern.starts_with('*');
    let ends_anchored = !normalized_pattern.ends_with('*');
    let mut cursor = 0usize;

    for (index, part) in parts.iter().enumerate() {
        let Some(found_at) = path[cursor..].find(part) else {
            return false;
        };
        let absolute = cursor + found_at;
        if index == 0 && starts_anchored && absolute != 0 {
            return false;
        }
        cursor = absolute + part.len();
    }

    if ends_anchored {
        let last = parts.last().copied().unwrap_or_default();
        path.ends_with(last)
    } else {
        true
    }
}

fn parse_kind(raw: &str) -> Option<SwiftBoundaryKind> {
    match raw {
        "ui_view" => Some(SwiftBoundaryKind::UiView),
        "binding_adapter" => Some(SwiftBoundaryKind::BindingAdapter),
        "apple_bootstrap" => Some(SwiftBoundaryKind::AppleBootstrap),
        _ => None,
    }
}

fn normalize_pattern(pattern: &str) -> String {
    pattern.replace("**", "*")
}

#[cfg(test)]
mod tests {
    use super::matches;

    #[test]
    fn matches_wildcard_prefix_suffix_and_middle() {
        assert!(matches(
            "App/*/Views/*",
            "App/SoloCodeApp/Sources/Views/Foo.swift"
        ));
        assert!(matches(
            "*/AppDelegate*.swift",
            "App/SoloCodeApp/Sources/App/AppDelegate.swift"
        ));
        assert!(!matches(
            "App/*/Views/*",
            "Engine/CoderEngine/Sources/CodeReview/Foo.swift"
        ));
    }
}
