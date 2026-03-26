use app_core_protocol::main_chat_provider::MainChatProviderAttachment;
use base64::Engine;
use std::collections::{BTreeMap, HashSet};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

pub(crate) fn apple_reference_seconds() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
        - 978_307_200.0
}

pub(crate) fn join_cli_prompt(
    system_prompt: Option<&str>,
    prompt: &str,
    context_prompt: Option<&str>,
    attachments: &[MainChatProviderAttachment],
) -> String {
    let mut parts = Vec::new();
    let image_refs = attachments
        .iter()
        .filter(|attachment| attachment.kind == "image")
        .map(|attachment| format!("[Image: {}]", attachment.file_path))
        .collect::<Vec<_>>();
    if !image_refs.is_empty() {
        parts.push(image_refs.join("\n"));
    }
    if let Some(system_prompt) = system_prompt.filter(|value| !value.trim().is_empty()) {
        parts.push(system_prompt.to_string());
    }
    parts.push(prompt.to_string());
    if let Some(context_prompt) = context_prompt.filter(|value| !value.trim().is_empty()) {
        parts.push(context_prompt.to_string());
    }
    parts.join("\n\n")
}

pub(crate) fn api_user_prompt(prompt: &str, context_prompt: Option<&str>) -> String {
    match context_prompt.filter(|value| !value.trim().is_empty()) {
        Some(context_prompt) => format!("{prompt}{context_prompt}"),
        None => prompt.to_string(),
    }
}

pub(crate) fn image_data_urls(
    attachments: &[MainChatProviderAttachment],
) -> Vec<BTreeMap<String, String>> {
    attachments
        .iter()
        .filter(|attachment| attachment.kind == "image")
        .filter_map(|attachment| {
            let bytes = std::fs::read(&attachment.file_path).ok()?;
            let mime = attachment
                .mime_type
                .clone()
                .unwrap_or_else(|| "image/jpeg".to_string());
            let encoded = base64::engine::general_purpose::STANDARD.encode(bytes);
            let mut item = BTreeMap::new();
            item.insert("type".to_string(), "image_url".to_string());
            item.insert("url".to_string(), format!("data:{mime};base64,{encoded}"));
            Some(item)
        })
        .collect()
}

pub(crate) fn flatten_string_map(value: &serde_json::Value) -> BTreeMap<String, String> {
    let mut payload = BTreeMap::new();
    if let Some(object) = value.as_object() {
        for (key, value) in object {
            if let Some(text) = string_value(value) {
                payload.insert(key.clone(), text);
            }
        }
    }
    payload
}

pub(crate) fn string_value(value: &serde_json::Value) -> Option<String> {
    match value {
        serde_json::Value::Null => None,
        serde_json::Value::Bool(flag) => Some(flag.to_string()),
        serde_json::Value::Number(number) => Some(number.to_string()),
        serde_json::Value::String(text) => {
            let trimmed = text.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        }
        serde_json::Value::Array(_) | serde_json::Value::Object(_) => {
            serde_json::to_string(value).ok()
        }
    }
}

pub(crate) fn retry_delay_ms(attempt: i32, retry_after_seconds: Option<i64>) -> i64 {
    if let Some(retry_after_seconds) = retry_after_seconds {
        return retry_after_seconds.max(1) * 1000;
    }
    let base = 500_i64;
    let multiplier = 2_i64.saturating_pow(attempt.max(0) as u32);
    (base * multiplier).min(8_000)
}

/// Molti CLI (Codex, Gemini, …) sono shim `#!/usr/bin/env node`. Le app macOS avviate da GUI
/// hanno spesso un PATH minimale → `env: node: No such file or directory` e exit 127.
/// Antepone directory comuni (Homebrew, Volta, nvm, …) al PATH esistente.
pub(crate) fn path_for_node_based_cli(existing_path: &str) -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    let mut ordered: Vec<String> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();

    let mut push_dir = |dir: String| {
        if dir.is_empty() {
            return;
        }
        if Path::new(&dir).is_dir() && seen.insert(dir.clone()) {
            ordered.push(dir);
        }
    };

    for d in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
        push_dir(d.to_string());
    }
    for rel in [
        ".volta/bin",
        ".bun/bin",
        ".local/bin",
        ".npm/bin",
        ".yarn/bin",
    ] {
        push_dir(format!("{home}/{rel}"));
    }
    push_dir(format!("{home}/.asdf/shims"));

    let nvm_versions = format!("{home}/.nvm/versions/node");
    let nvm_path = Path::new(&nvm_versions);
    let default_link = nvm_path.join("default");
    if let Ok(target) = std::fs::read_link(&default_link) {
        let resolved = default_link
            .parent()
            .unwrap_or(nvm_path)
            .join(target)
            .join("bin");
        if resolved.is_dir() {
            push_dir(resolved.to_string_lossy().into_owned());
        }
    } else if let Ok(rd) = std::fs::read_dir(&nvm_versions) {
        let mut versions: Vec<_> = rd
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| p.is_dir())
            .collect();
        versions.sort();
        if let Some(vdir) = versions.last() {
            let bin = vdir.join("bin");
            if bin.is_dir() {
                push_dir(bin.to_string_lossy().into_owned());
            }
        }
    }

    for seg in existing_path.split(':').filter(|s| !s.is_empty()) {
        let s = seg.to_string();
        if seen.insert(s.clone()) {
            ordered.push(s);
        }
    }

    ordered.join(":")
}

pub(crate) fn apply_gui_safe_cli_path(environment: &mut BTreeMap<String, String>) {
    let prior = environment.get("PATH").map(|s| s.as_str()).unwrap_or("");
    environment.insert("PATH".to_string(), path_for_node_based_cli(prior));
}

#[cfg(test)]
mod path_tests {
    use super::path_for_node_based_cli;

    #[test]
    fn path_for_node_based_cli_preserves_existing_segments() {
        let p = path_for_node_based_cli("/tmp/foo:/usr/bin");
        assert!(p.contains("/tmp/foo"));
        assert!(p.contains("/usr/bin"));
    }
}
