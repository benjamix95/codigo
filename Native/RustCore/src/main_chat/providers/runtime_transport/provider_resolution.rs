use app_core_protocol::main_chat_provider::{
    MainChatCLIAccountSnapshot, MainChatProviderBackend, MainChatRuntimeTransportRequest,
};

pub(super) fn resolve_provider_id(
    request: &MainChatRuntimeTransportRequest,
    read_only_plan: bool,
) -> Option<String> {
    let selected_provider_id = normalized_optional_string(request.selected_provider_id.as_deref())
        .or_else(|| normalized_optional_string(request.fallback_selected_provider_id.as_deref()))
        .map(|provider_id| canonical_provider_id(&provider_id).unwrap_or(provider_id));
    if read_only_plan {
        return Some(resolve_swarm_backend_id(
            &request.plan_mode_backend,
            selected_provider_id.as_deref(),
        ));
    }
    if request.prefer_code_review_runtime_provider.unwrap_or(false)
        || normalized_mode(request.coder_mode.as_deref()) == "codereview"
    {
        return Some(resolve_swarm_backend_id(
            &request.code_review_execution_backend,
            selected_provider_id.as_deref(),
        ));
    }
    selected_provider_id
}

pub(super) fn backend_for_provider_id(provider_id: &str) -> Option<MainChatProviderBackend> {
    match normalized_backend_id(provider_id).as_str() {
        "codex" | "codex-cli" => Some(MainChatProviderBackend::CodexCli),
        "claude" | "claude-cli" => Some(MainChatProviderBackend::ClaudeCli),
        "gemini" | "gemini-cli" => Some(MainChatProviderBackend::GeminiCli),
        "openai" | "openai-api" => Some(MainChatProviderBackend::OpenaiApi),
        "anthropic-api" => Some(MainChatProviderBackend::AnthropicApi),
        "google-api" => Some(MainChatProviderBackend::GoogleApi),
        _ => None,
    }
}

pub(super) fn normalized_string(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

pub(super) fn normalized_mode(raw: Option<&str>) -> String {
    raw.unwrap_or_default()
        .trim()
        .replace([' ', '-'], "")
        .to_lowercase()
}

pub(super) fn resolve_transport_authentication(
    provider_id: &str,
    request: &MainChatRuntimeTransportRequest,
) -> bool {
    let base_authenticated = request
        .registry_providers
        .iter()
        .find(|provider| provider.id == provider_id)
        .map(|provider| provider.is_authenticated)
        .unwrap_or(false);
    if base_authenticated {
        return true;
    }
    match normalized_backend_id(provider_id).as_str() {
        "codex" | "codex-cli" => has_authenticated_cli_account(&request.codex_cli_accounts),
        "claude" | "claude-cli" => has_authenticated_cli_account(&request.claude_cli_accounts),
        "gemini" | "gemini-cli" => has_authenticated_cli_account(&request.gemini_cli_accounts),
        _ => false,
    }
}

pub(super) fn attachment_capabilities(provider_id: &str) -> (bool, bool, bool) {
    match normalized_backend_id(provider_id).as_str() {
        "codex" | "codex-cli" | "claude" | "claude-cli" | "openai" | "openai-api"
        | "anthropic-api" => (true, false, false),
        _ => (false, false, false),
    }
}

pub(super) fn normalized_backend_id(raw: &str) -> String {
    raw.trim().to_lowercase()
}

fn normalized_optional_string(raw: Option<&str>) -> Option<String> {
    raw.and_then(normalized_string)
}

fn resolve_swarm_backend_id(
    configured_backend_id: &str,
    agent_provider_id: Option<&str>,
) -> String {
    let normalized = normalized_backend_id(configured_backend_id);
    if normalized.is_empty() || normalized == "auto" {
        return swarm_backend_id_for_agent_provider(agent_provider_id)
            .map(|backend_id| canonical_provider_id(&backend_id).unwrap_or(backend_id))
            .unwrap_or_else(|| "codex-cli".to_string());
    }
    canonical_provider_id(&normalized).unwrap_or(normalized)
}

fn swarm_backend_id_for_agent_provider(provider_id: Option<&str>) -> Option<String> {
    match normalized_backend_id(provider_id.unwrap_or_default()).as_str() {
        "codex-cli" | "codex" => Some("codex".to_string()),
        "claude-cli" | "claude" => Some("claude".to_string()),
        "gemini-cli" | "gemini" => Some("gemini".to_string()),
        "openai-api" | "openai" => Some("openai-api".to_string()),
        "anthropic-api" => Some("anthropic-api".to_string()),
        "google-api" => Some("google-api".to_string()),
        "openrouter-api" | "openrouter" => Some("openrouter-api".to_string()),
        "minimax-api" => Some("minimax-api".to_string()),
        "grok-api" => Some("grok-api".to_string()),
        _ => None,
    }
}

fn canonical_provider_id(raw: &str) -> Option<String> {
    match normalized_backend_id(raw).as_str() {
        "codex" | "codex-cli" => Some("codex-cli".to_string()),
        "claude" | "claude-cli" => Some("claude-cli".to_string()),
        "gemini" | "gemini-cli" => Some("gemini-cli".to_string()),
        "openai" | "openai-api" => Some("openai-api".to_string()),
        "anthropic-api" => Some("anthropic-api".to_string()),
        "google-api" => Some("google-api".to_string()),
        "openrouter" | "openrouter-api" => Some("openrouter-api".to_string()),
        "minimax-api" => Some("minimax-api".to_string()),
        "grok-api" => Some("grok-api".to_string()),
        _ => None,
    }
}

fn has_authenticated_cli_account(accounts: &[MainChatCLIAccountSnapshot]) -> bool {
    accounts
        .iter()
        .any(|account| account.is_enabled && account.is_authenticated)
}
