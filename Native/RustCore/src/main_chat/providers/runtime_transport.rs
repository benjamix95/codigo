use app_core_protocol::main_chat_provider::{
    MainChatCLIAccountSnapshot, MainChatProviderBackend, MainChatRuntimeTransportRequest,
    MainChatRuntimeTransportResponse,
};
use std::collections::BTreeMap;

const READ_ONLY_CLAUDE_TOOLS: &[&str] = &["Read", "Glob", "Grep"];

pub fn resolve_runtime_transport(
    request: MainChatRuntimeTransportRequest,
) -> MainChatRuntimeTransportResponse {
    if request.schema_version != 1 {
        return MainChatRuntimeTransportResponse::error(
            "unsupported_schema",
            "schemaVersion must be 1",
        );
    }

    let read_only_plan = request.force_plan_inline
        || request.should_run_plan_inline
        || normalized_mode(request.coder_mode.as_deref()) == "plan";
    let provider_id = match resolve_provider_id(&request, read_only_plan) {
        Some(provider_id) => provider_id,
        None => {
            return MainChatRuntimeTransportResponse::error(
                "missing_provider_id",
                "Unable to resolve runtime transport provider id",
            )
        }
    };
    let backend = match backend_for_provider_id(&provider_id) {
        Some(backend) => backend,
        None => {
            return MainChatRuntimeTransportResponse::error(
                "unsupported_provider_id",
                "Unsupported runtime transport provider id",
            )
        }
    };
    let claude_allowed_tools = if read_only_plan {
        READ_ONLY_CLAUDE_TOOLS.iter().map(|tool| tool.to_string()).collect()
    } else {
        request.claude_allowed_tools.clone()
    };
    let codex_sandbox = if read_only_plan {
        Some("workspace-read".to_string())
    } else {
        normalized_string(&request.codex_sandbox)
    };
    let codex_session_full_access = if read_only_plan {
        false
    } else {
        request.codex_session_full_access
    };

    let (model, api_key, base_url) = match backend {
        MainChatProviderBackend::CodexCli => (
            normalized_string(&request.codex_model_override),
            None,
            None,
        ),
        MainChatProviderBackend::ClaudeCli => (
            normalized_string(&request.claude_model),
            None,
            None,
        ),
        MainChatProviderBackend::GeminiCli => (
            normalized_string(&request.gemini_model_override),
            None,
            None,
        ),
        MainChatProviderBackend::OpenaiApi => (
            normalized_string(&request.openai_model),
            normalized_string(&request.openai_api_key),
            Some("https://api.openai.com/v1/chat/completions".to_string()),
        ),
        MainChatProviderBackend::AnthropicApi => (
            normalized_string(&request.anthropic_model),
            normalized_string(&request.anthropic_api_key),
            Some("https://api.anthropic.com/v1/messages".to_string()),
        ),
        MainChatProviderBackend::GoogleApi => (
            normalized_string(&request.google_model),
            normalized_string(&request.google_api_key),
            Some("https://generativelanguage.googleapis.com/v1beta/openai/chat/completions".to_string()),
        ),
    };
    let is_authenticated = resolve_transport_authentication(&provider_id, &request);
    let (native_image_attachment, native_document_attachment, native_file_attachment) =
        attachment_capabilities(&provider_id);
    let multi_account_policy = resolve_multi_account_policy(&provider_id, &request);

    MainChatRuntimeTransportResponse::success(
        provider_id,
        backend,
        model,
        api_key,
        base_url,
        BTreeMap::new(),
        codex_sandbox,
        codex_session_full_access,
        claude_allowed_tools,
        read_only_plan,
        is_authenticated,
        native_image_attachment,
        native_document_attachment,
        native_file_attachment,
        multi_account_policy.fallback_allowed,
        multi_account_policy.use_single_configured_provider,
        multi_account_policy.failure_reason,
        multi_account_policy.user_facing_hint,
    )
}

fn resolve_provider_id(request: &MainChatRuntimeTransportRequest, read_only_plan: bool) -> Option<String> {
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

fn resolve_swarm_backend_id(configured_backend_id: &str, agent_provider_id: Option<&str>) -> String {
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

fn backend_for_provider_id(provider_id: &str) -> Option<MainChatProviderBackend> {
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

fn normalized_optional_string(raw: Option<&str>) -> Option<String> {
    raw.and_then(normalized_string)
}

fn normalized_string(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn normalized_backend_id(raw: &str) -> String {
    raw.trim().to_lowercase()
}

fn normalized_mode(raw: Option<&str>) -> String {
    raw.unwrap_or_default()
        .trim()
        .replace([' ', '-'], "")
        .to_lowercase()
}

fn resolve_transport_authentication(
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

fn has_authenticated_cli_account(accounts: &[MainChatCLIAccountSnapshot]) -> bool {
    accounts
        .iter()
        .any(|account| account.is_enabled && account.is_authenticated)
}

fn attachment_capabilities(provider_id: &str) -> (bool, bool, bool) {
    match normalized_backend_id(provider_id).as_str() {
        "codex" | "codex-cli" | "claude" | "claude-cli" | "openai" | "openai-api"
        | "anthropic-api" => (true, false, false),
        _ => (false, false, false),
    }
}

struct MultiAccountPolicy {
    fallback_allowed: bool,
    use_single_configured_provider: bool,
    failure_reason: Option<String>,
    user_facing_hint: Option<String>,
}

fn resolve_multi_account_policy(
    provider_id: &str,
    request: &MainChatRuntimeTransportRequest,
) -> MultiAccountPolicy {
    if !request.multi_cli_account_enabled {
        return MultiAccountPolicy {
            fallback_allowed: false,
            use_single_configured_provider: false,
            failure_reason: None,
            user_facing_hint: None,
        };
    }
    let is_cli_provider = matches!(
        normalized_backend_id(provider_id).as_str(),
        "codex" | "codex-cli" | "claude" | "claude-cli" | "gemini" | "gemini-cli"
    );
    if !is_cli_provider {
        return MultiAccountPolicy {
            fallback_allowed: false,
            use_single_configured_provider: false,
            failure_reason: None,
            user_facing_hint: None,
        };
    }

    let availability_status = normalized_string(
        request
            .provider_availability_status
            .as_deref()
            .unwrap_or_default(),
    )
    .unwrap_or_default()
    .to_lowercase();

    if availability_status != "all_exhausted" {
        return MultiAccountPolicy {
            fallback_allowed: false,
            use_single_configured_provider: false,
            failure_reason: None,
            user_facing_hint: None,
        };
    }

    let failure_reason = normalized_string(
        request
            .provider_availability_reason
            .as_deref()
            .unwrap_or_default(),
    );
    let provider_label = provider_display_name(provider_id);
    if request.base_authenticated {
        let reason = failure_reason
            .clone()
            .unwrap_or_else(|| "No available account".to_string());
        return MultiAccountPolicy {
            fallback_allowed: true,
            use_single_configured_provider: true,
            failure_reason: Some(reason.clone()),
            user_facing_hint: Some(format!(
                "[Multi-account {}: {}. Falling back to the single configured CLI provider for this turn.]",
                provider_label, reason
            )),
        };
    }

    let reason = failure_reason
        .clone()
        .unwrap_or_else(|| "No available account".to_string());
    MultiAccountPolicy {
        fallback_allowed: false,
        use_single_configured_provider: false,
        failure_reason: Some(reason.clone()),
        user_facing_hint: Some(format!(
            "[Multi-account {}: {}. Configure accounts or reset limits in Settings.]",
            provider_label, reason
        )),
    }
}

fn provider_display_name(provider_id: &str) -> &'static str {
    match normalized_backend_id(provider_id).as_str() {
        "codex" | "codex-cli" => "Codex CLI",
        "claude" | "claude-cli" => "Claude CLI",
        "gemini" | "gemini-cli" => "Gemini CLI",
        _ => "CLI",
    }
}

#[cfg(test)]
mod tests {
    use super::resolve_runtime_transport;
    use app_core_protocol::main_chat_provider::{
        MainChatCLIAccountSnapshot, MainChatProviderBackend,
        MainChatRuntimeProviderRegistryEntry, MainChatRuntimeTransportRequest,
    };
    use std::collections::BTreeMap;

    #[test]
    fn read_only_plan_uses_plan_backend_and_locked_permissions() {
        let response = resolve_runtime_transport(request(
            "openai-api",
            Some("openai-api"),
            true,
            false,
            None,
        ));
        assert_eq!(response.provider_id.as_deref(), Some("openai-api"));
        assert_eq!(response.backend, Some(MainChatProviderBackend::OpenaiApi));
        assert!(response.read_only_plan);
        assert_eq!(response.codex_sandbox.as_deref(), Some("workspace-read"));
        assert!(!response.codex_session_full_access);
        assert_eq!(response.claude_allowed_tools, vec!["Read", "Glob", "Grep"]);
        assert!(response.is_authenticated);
        assert!(response.native_image_attachment);
        assert!(!response.native_document_attachment);
        assert!(!response.native_file_attachment);
        assert!(!response.fallback_allowed);
        assert!(!response.use_single_configured_provider);
    }

    #[test]
    fn code_review_prefers_execution_backend() {
        let response = resolve_runtime_transport(request(
            "codex-cli",
            Some("claude-cli"),
            false,
            false,
            Some(true),
        ));
        assert_eq!(response.provider_id.as_deref(), Some("claude-cli"));
        assert_eq!(response.backend, Some(MainChatProviderBackend::ClaudeCli));
        assert_eq!(response.model.as_deref(), Some("claude-3"));
        assert!(response.is_authenticated);
    }

    #[test]
    fn cli_account_authentication_can_mark_transport_authenticated() {
        let mut request = request("codex-cli", Some("codex-cli"), false, false, None);
        request.registry_providers = vec![registry_provider("codex-cli", false)];
        request.codex_cli_accounts = vec![cli_account(true, true)];

        let response = resolve_runtime_transport(request);
        assert_eq!(response.provider_id.as_deref(), Some("codex-cli"));
        assert!(response.is_authenticated);
    }

    #[test]
    fn exhausted_multi_account_can_fallback_to_single_configured_provider() {
        let mut request = request("codex-cli", Some("codex-cli"), false, false, None);
        request.multi_cli_account_enabled = true;
        request.provider_availability_status = Some("all_exhausted".to_string());
        request.provider_availability_reason = Some("Daily limit reached".to_string());
        request.base_authenticated = true;

        let response = resolve_runtime_transport(request);
        assert!(response.fallback_allowed);
        assert!(response.use_single_configured_provider);
        assert_eq!(response.failure_reason.as_deref(), Some("Daily limit reached"));
        assert!(response
            .user_facing_hint
            .as_deref()
            .unwrap_or_default()
            .contains("Falling back"));
    }

    #[test]
    fn exhausted_multi_account_without_base_auth_fails_closed() {
        let mut request = request("codex-cli", Some("codex-cli"), false, false, None);
        request.multi_cli_account_enabled = true;
        request.provider_availability_status = Some("all_exhausted".to_string());
        request.provider_availability_reason = Some("Daily limit reached".to_string());
        request.base_authenticated = false;

        let response = resolve_runtime_transport(request);
        assert!(!response.fallback_allowed);
        assert!(!response.use_single_configured_provider);
        assert_eq!(response.failure_reason.as_deref(), Some("Daily limit reached"));
        assert!(response
            .user_facing_hint
            .as_deref()
            .unwrap_or_default()
            .contains("Configure accounts"));
    }

    #[test]
    fn falls_back_to_selected_provider_when_no_special_mode_is_active() {
        let response = resolve_runtime_transport(request(
            "codex-cli",
            None,
            false,
            false,
            None,
        ));
        assert_eq!(response.provider_id.as_deref(), Some("codex-cli"));
        assert_eq!(response.backend, Some(MainChatProviderBackend::CodexCli));
        assert_eq!(response.model.as_deref(), Some("o3"));
    }

    fn request(
        fallback_selected_provider_id: &str,
        selected_provider_id: Option<&str>,
        should_run_plan_inline: bool,
        force_plan_inline: bool,
        prefer_code_review_runtime_provider: Option<bool>,
    ) -> MainChatRuntimeTransportRequest {
        MainChatRuntimeTransportRequest {
            schema_version: 1,
            selected_provider_id: selected_provider_id.map(str::to_string),
            fallback_selected_provider_id: Some(fallback_selected_provider_id.to_string()),
            coder_mode: Some("Agent".to_string()),
            should_run_plan_inline,
            force_plan_inline,
            prefer_code_review_runtime_provider,
            plan_mode_backend: "openai-api".to_string(),
            code_review_execution_backend: "claude".to_string(),
            openai_api_key: "sk-openai".to_string(),
            openai_model: "gpt-5".to_string(),
            anthropic_api_key: "sk-anthropic".to_string(),
            anthropic_model: "claude-api".to_string(),
            google_api_key: "sk-google".to_string(),
            google_model: "gemini-api".to_string(),
            codex_model_override: "o3".to_string(),
            codex_sandbox: "workspace-write".to_string(),
            codex_session_full_access: true,
            claude_model: "claude-3".to_string(),
            claude_allowed_tools: vec!["Read".to_string(), "Edit".to_string()],
            gemini_model_override: "gemini-2.5".to_string(),
            registry_providers: vec![
                registry_provider("codex-cli", true),
                registry_provider("claude-cli", true),
                registry_provider("openai-api", true),
            ],
            codex_cli_accounts: Vec::new(),
            claude_cli_accounts: Vec::new(),
            gemini_cli_accounts: Vec::new(),
            multi_cli_account_enabled: false,
            provider_availability_status: None,
            provider_availability_reason: None,
            base_authenticated: false,
        }
    }

    fn registry_provider(id: &str, is_authenticated: bool) -> MainChatRuntimeProviderRegistryEntry {
        MainChatRuntimeProviderRegistryEntry {
            id: id.to_string(),
            is_authenticated,
        }
    }

    fn cli_account(is_enabled: bool, is_authenticated: bool) -> MainChatCLIAccountSnapshot {
        MainChatCLIAccountSnapshot {
            id: "account-1".to_string(),
            provider: "codex".to_string(),
            label: "Primary".to_string(),
            is_enabled,
            is_authenticated,
            priority: 0,
            profile_path: "/tmp/profile".to_string(),
            env_overrides: BTreeMap::new(),
            quota: Default::default(),
            health: Default::default(),
            created_at: None,
            updated_at: None,
        }
    }
}
