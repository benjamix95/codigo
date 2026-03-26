use app_core_protocol::thread_provider_selection::{
    ThreadProviderRegistryEntry, ThreadProviderSelectionRequest, ThreadProviderSelectionResponse,
};

const AGENT_PROVIDER_IDS: &[&str] =
    &["codex-cli", "claude-cli", "gemini-cli", "kilo-cli"];
const AGENT_API_PROVIDER_IDS: &[&str] = &[
    "openai-api",
    "anthropic-api",
    "google-api",
    "openrouter-api",
    "minimax-api",
    "grok-api",
];
const ALL_AGENT_PROVIDER_IDS: &[&str] = &[
    "codex-cli",
    "claude-cli",
    "gemini-cli",
    "kilo-cli",
    "openai-api",
    "anthropic-api",
    "google-api",
    "openrouter-api",
    "minimax-api",
    "grok-api",
];
const PREFERRED_IDE_PROVIDER_IDS: &[&str] = &[
    "openai-api",
    "anthropic-api",
    "google-api",
    "openrouter-api",
    "minimax-api",
    "grok-api",
];

pub fn resolve_thread_provider_selection(
    request: ThreadProviderSelectionRequest,
) -> ThreadProviderSelectionResponse {
    if request.schema_version != 1 {
        return ThreadProviderSelectionResponse::error(
            "unsupported_schema",
            "schemaVersion must be 1",
        );
    }

    let mode = normalize_mode(request.conversation_mode.as_deref());
    let preferred = normalize_provider_id(request.preferred_provider_id.as_deref());
    let current = normalize_provider_id(request.current_provider_id.as_deref());
    let selected = normalize_provider_id(request.selected_provider_id.as_deref());
    let registry_selected = normalize_provider_id(request.registry_selected_provider_id.as_deref());

    let resolved_provider_id = if mode == "MCP Server" {
        Some("claude-cli".to_string())
    } else if preferred
        .as_deref()
        .map(|provider| is_provider_allowed(provider, mode))
        .unwrap_or(false)
    {
        preferred.clone()
    } else {
        fallback_provider_id(
            mode,
            current.as_deref(),
            registry_selected.as_deref(),
            &request.registry_providers,
        )
    };

    let missing_bound_provider_id = preferred
        .as_deref()
        .or(selected.as_deref())
        .filter(|provider| is_provider_allowed(provider, mode))
        .filter(|provider| !provider_registered(provider, &request.registry_providers))
        .map(str::to_string);

    ThreadProviderSelectionResponse::success(mode, resolved_provider_id, missing_bound_provider_id)
}

fn normalize_mode(raw: Option<&str>) -> &'static str {
    match raw.unwrap_or_default().trim() {
        "Code Review" => "Code Review",
        "Debug" => "Debug",
        "Plan" => "Plan",
        "IDE" => "IDE",
        "Browser" => "Browser",
        "MCP Server" => "MCP Server",
        _ => "Agent",
    }
}

fn normalize_provider_id(raw: Option<&str>) -> Option<String> {
    let trimmed = raw.unwrap_or_default().trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn fallback_provider_id(
    mode: &str,
    current: Option<&str>,
    registry_selected: Option<&str>,
    registry_providers: &[ThreadProviderRegistryEntry],
) -> Option<String> {
    match mode {
        "IDE" => {
            if current
                .filter(|provider| is_provider_allowed(provider, "IDE"))
                .filter(|provider| provider_registered(provider, registry_providers))
                .is_some()
            {
                return current.map(str::to_string);
            }
            Some(preferred_ide_provider(
                registry_selected,
                registry_providers,
            ))
        }
        "Agent" | "Code Review" | "Debug" | "Plan" | "Browser" => {
            if current
                .filter(|provider| is_provider_allowed(provider, mode))
                .filter(|provider| provider_registered(provider, registry_providers))
                .is_some()
            {
                return current.map(str::to_string);
            }
            first_healthy_agent_provider_id(registry_providers)
                .or_else(|| first_registered_agent_compatible_provider_id(registry_providers))
        }
        "MCP Server" => Some("claude-cli".to_string()),
        _ => None,
    }
}

fn preferred_ide_provider(
    registry_selected: Option<&str>,
    registry_providers: &[ThreadProviderRegistryEntry],
) -> String {
    if registry_selected
        .filter(|provider| is_ide_provider(provider))
        .filter(|provider| provider_authenticated(provider, registry_providers))
        .is_some()
    {
        return registry_selected.unwrap_or("openai-api").to_string();
    }
    for provider in PREFERRED_IDE_PROVIDER_IDS {
        if provider_authenticated(provider, registry_providers) {
            return provider.to_string();
        }
    }
    if let Some(provider) = registry_providers
        .iter()
        .find(|provider| is_ide_provider(&provider.id) && provider.is_authenticated)
    {
        return provider.id.clone();
    }
    if registry_selected
        .filter(|provider| is_ide_provider(provider))
        .is_some()
    {
        return registry_selected.unwrap_or("openai-api").to_string();
    }
    for provider in PREFERRED_IDE_PROVIDER_IDS {
        if provider_registered(provider, registry_providers) {
            return provider.to_string();
        }
    }
    if let Some(provider) = registry_providers
        .iter()
        .find(|provider| is_ide_provider(&provider.id))
    {
        return provider.id.clone();
    }
    "openai-api".to_string()
}

fn first_healthy_agent_provider_id(
    registry_providers: &[ThreadProviderRegistryEntry],
) -> Option<String> {
    ALL_AGENT_PROVIDER_IDS
        .iter()
        .find(|provider| provider_authenticated(provider, registry_providers))
        .map(|provider| provider.to_string())
}

fn first_registered_agent_compatible_provider_id(
    registry_providers: &[ThreadProviderRegistryEntry],
) -> Option<String> {
    for provider in ALL_AGENT_PROVIDER_IDS {
        if provider_registered(provider, registry_providers) {
            return Some(provider.to_string());
        }
    }
    registry_providers
        .iter()
        .find(|provider| is_agent_compatible_provider(&provider.id))
        .map(|provider| provider.id.clone())
}

fn provider_registered(provider: &str, registry_providers: &[ThreadProviderRegistryEntry]) -> bool {
    registry_providers.iter().any(|entry| entry.id == provider)
}

fn provider_authenticated(
    provider: &str,
    registry_providers: &[ThreadProviderRegistryEntry],
) -> bool {
    registry_providers
        .iter()
        .find(|entry| entry.id == provider)
        .map(|entry| entry.is_authenticated)
        .unwrap_or(false)
}

fn is_provider_allowed(provider: &str, mode: &str) -> bool {
    match mode {
        "IDE" => is_ide_provider(provider),
        "Agent" | "Code Review" | "Debug" | "Plan" | "Browser" => {
            is_agent_compatible_provider(provider)
        }
        "MCP Server" => provider == "claude-cli",
        _ => false,
    }
}

fn is_agent_compatible_provider(provider: &str) -> bool {
    AGENT_PROVIDER_IDS.contains(&provider) || AGENT_API_PROVIDER_IDS.contains(&provider)
}

fn is_ide_provider(provider: &str) -> bool {
    provider.ends_with("-api")
}

#[cfg(test)]
mod tests {
    use super::resolve_thread_provider_selection;
    use app_core_protocol::thread_provider_selection::{
        ThreadProviderRegistryEntry, ThreadProviderSelectionRequest,
    };

    #[test]
    fn keeps_bound_preferred_provider_even_when_missing() {
        let response = resolve_thread_provider_selection(request(
            Some("claude-cli"),
            Some("codex-cli"),
            vec![provider("codex-cli", true)],
        ));
        assert_eq!(response.resolved_provider_id.as_deref(), Some("claude-cli"));
    }

    #[test]
    fn agent_mode_falls_back_to_first_healthy_provider() {
        let response = resolve_thread_provider_selection(ThreadProviderSelectionRequest {
            registry_providers: vec![provider("codex-cli", false), provider("openai-api", true)],
            ..request(None, None, vec![])
        });
        assert_eq!(response.resolved_provider_id.as_deref(), Some("openai-api"));
    }

    #[test]
    fn ide_mode_prefers_authenticated_registry_selection() {
        let response = resolve_thread_provider_selection(ThreadProviderSelectionRequest {
            conversation_mode: Some("IDE".to_string()),
            registry_selected_provider_id: Some("anthropic-api".to_string()),
            registry_providers: vec![
                provider("openai-api", false),
                provider("anthropic-api", true),
            ],
            ..request(None, Some("openai-api"), vec![])
        });
        assert_eq!(response.resolved_provider_id.as_deref(), Some("openai-api"));
    }

    #[test]
    fn reports_missing_bound_provider_when_allowed_but_unregistered() {
        let response = resolve_thread_provider_selection(ThreadProviderSelectionRequest {
            selected_provider_id: Some("openrouter-api".to_string()),
            registry_providers: vec![provider("codex-cli", true)],
            ..request(None, None, vec![])
        });
        assert_eq!(
            response.missing_bound_provider_id.as_deref(),
            Some("openrouter-api")
        );
    }

    #[test]
    fn mcp_server_is_forced_to_claude_cli() {
        let response = resolve_thread_provider_selection(ThreadProviderSelectionRequest {
            conversation_mode: Some("MCP Server".to_string()),
            ..request(None, Some("openai-api"), vec![provider("openai-api", true)])
        });
        assert_eq!(response.effective_mode.as_deref(), Some("MCP Server"));
        assert_eq!(response.resolved_provider_id.as_deref(), Some("claude-cli"));
    }

    fn request(
        preferred_provider_id: Option<&str>,
        current_provider_id: Option<&str>,
        registry_providers: Vec<ThreadProviderRegistryEntry>,
    ) -> ThreadProviderSelectionRequest {
        ThreadProviderSelectionRequest {
            schema_version: 1,
            conversation_mode: None,
            preferred_provider_id: preferred_provider_id.map(str::to_string),
            current_provider_id: current_provider_id.map(str::to_string),
            selected_provider_id: None,
            registry_selected_provider_id: current_provider_id.map(str::to_string),
            registry_providers,
        }
    }

    fn provider(id: &str, is_authenticated: bool) -> ThreadProviderRegistryEntry {
        ThreadProviderRegistryEntry {
            id: id.to_string(),
            is_authenticated,
        }
    }
}
