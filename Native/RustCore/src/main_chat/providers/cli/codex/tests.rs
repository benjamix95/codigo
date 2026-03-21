use super::{normalize_tool_name, resolve_codex_executable_with};
use app_core_protocol::main_chat_provider::{
    MainChatCLIAccountSnapshot, MainChatCLIHealthSnapshot, MainChatCLIQuotaSnapshot,
    MainChatProviderSessionConfig,
};
use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;

#[test]
fn normalizes_codex_tool_names() {
    assert_eq!(normalize_tool_name("planRequestUserInput"), "plan_request_user_input");
    assert_eq!(normalize_tool_name("mermaidRender"), "mermaid_render");
}

#[test]
fn resolves_codex_executable_from_account_override_before_config() {
    let account_path = temp_file("account-codex");
    let config_path = temp_file("config-codex");
    let detected_path = temp_file("detected-codex");
    let config = provider_config(Some(&config_path));
    let account = cli_account(Some(&account_path));
    let resolved = resolve_codex_executable_with(Some(&account), &config, || Some(detected_path.clone()));
    assert_eq!(resolved.as_deref(), Ok(account_path.as_str()));
}

#[test]
fn resolves_codex_executable_from_config_when_override_is_invalid() {
    let config_path = temp_file("config-codex");
    let detected_path = temp_file("detected-codex");
    let config = provider_config(Some(&config_path));
    let account = cli_account(Some("/tmp/missing-codex"));
    let resolved = resolve_codex_executable_with(Some(&account), &config, || Some(detected_path.clone()));
    assert_eq!(resolved.as_deref(), Ok(config_path.as_str()));
}

#[test]
fn resolves_codex_executable_from_detector_when_other_sources_missing() {
    let detected_path = temp_file("detected-codex");
    let config = provider_config(None);
    let resolved = resolve_codex_executable_with(None, &config, || Some(detected_path.clone()));
    assert_eq!(resolved.as_deref(), Ok(detected_path.as_str()));
}

#[test]
fn returns_missing_codex_path_when_no_source_is_valid() {
    let config = provider_config(None);
    let resolved = resolve_codex_executable_with(None, &config, || Some("/tmp/missing-codex".to_string()));
    assert_eq!(resolved.unwrap_err(), "missing_codex_path");
}

fn provider_config(codex_path: Option<&str>) -> MainChatProviderSessionConfig {
    MainChatProviderSessionConfig {
        provider_id: "codex-cli".to_string(),
        display_name: "Codex".to_string(),
        workspace_path: ".".to_string(),
        workspace_paths: vec![".".to_string()],
        prompt: "hello".to_string(),
        codex_path: codex_path.map(str::to_string),
        ..Default::default()
    }
}

fn cli_account(codex_path: Option<&str>) -> MainChatCLIAccountSnapshot {
    let mut env_overrides = BTreeMap::new();
    if let Some(codex_path) = codex_path {
        env_overrides.insert("CODEX_PATH".to_string(), codex_path.to_string());
    }
    MainChatCLIAccountSnapshot {
        id: "account-1".to_string(),
        provider: "codex".to_string(),
        label: "Primary".to_string(),
        is_enabled: true,
        is_authenticated: true,
        priority: 0,
        profile_path: "/tmp/codex".to_string(),
        env_overrides,
        quota: MainChatCLIQuotaSnapshot::default(),
        health: MainChatCLIHealthSnapshot::default(),
        created_at: None,
        updated_at: None,
    }
}

fn temp_file(name: &str) -> String {
    let mut path = std::env::temp_dir();
    path.push(format!("solocode-{name}-{}", std::process::id()));
    write_temp_file(&path);
    path.to_string_lossy().into_owned()
}

fn write_temp_file(path: &PathBuf) {
    fs::write(path, "codex").expect("write temp codex path");
}
