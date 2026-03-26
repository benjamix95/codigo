use super::provider_resolution::{normalized_backend_id, normalized_string};
use app_core_protocol::main_chat_provider::{
    MainChatRuntimeExecutionStrategy, MainChatRuntimeTransportRequest,
};

pub(super) struct MultiAccountPolicy {
    pub fallback_allowed: bool,
    pub use_single_configured_provider: bool,
    pub execution_strategy: MainChatRuntimeExecutionStrategy,
    pub failure_reason: Option<String>,
    pub user_facing_hint: Option<String>,
}

pub(super) fn resolve_multi_account_policy(
    provider_id: &str,
    request: &MainChatRuntimeTransportRequest,
) -> MultiAccountPolicy {
    if !request.multi_cli_account_enabled {
        return MultiAccountPolicy {
            fallback_allowed: false,
            use_single_configured_provider: false,
            execution_strategy: MainChatRuntimeExecutionStrategy::SelectedProvider,
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
            execution_strategy: MainChatRuntimeExecutionStrategy::SelectedProvider,
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
            execution_strategy: MainChatRuntimeExecutionStrategy::MultiAccountRouter,
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
            execution_strategy: MainChatRuntimeExecutionStrategy::SingleConfiguredProvider,
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
        execution_strategy: MainChatRuntimeExecutionStrategy::FailClosed,
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
        "kilo" | "kilo-cli" => "Kilo CLI",
        _ => "CLI",
    }
}
