use app_core_protocol::main_chat_provider::{
    MainChatCLIAccountSnapshot, MainChatCLIHealthSnapshot, MainChatCLIQuotaSnapshot,
};

pub(crate) fn available_cli_accounts(
    accounts: &[MainChatCLIAccountSnapshot],
    provider: &str,
    now: f64,
) -> Vec<MainChatCLIAccountSnapshot> {
    let mut items = accounts
        .iter()
        .filter(|account| account.provider == provider)
        .filter(|account| account.is_enabled)
        .filter(|account| account.is_authenticated)
        .filter(|account| !account.health.is_exhausted_locally)
        .filter(|account| cooldown_expired(&account.health, now))
        .filter(|account| !quota_exhausted(&account.quota))
        .cloned()
        .collect::<Vec<_>>();
    items.sort_by(|lhs, rhs| {
        lhs.priority
            .cmp(&rhs.priority)
            .then_with(|| lhs.created_at.partial_cmp(&rhs.created_at).unwrap_or(std::cmp::Ordering::Equal))
            .then_with(|| lhs.id.cmp(&rhs.id))
    });
    items
}

pub(crate) fn select_active_cli_account(
    accounts: &[MainChatCLIAccountSnapshot],
    provider: &str,
    round_robin_index: i32,
    current_active_id: Option<&str>,
    now: f64,
) -> Option<(MainChatCLIAccountSnapshot, i32)> {
    let available = available_cli_accounts(accounts, provider, now);
    if available.is_empty() {
        return None;
    }
    if let Some(current_active_id) = current_active_id {
        if let Some(existing) = available.iter().find(|account| account.id == current_active_id) {
            return Some((existing.clone(), round_robin_index));
        }
    }
    let current_index = (round_robin_index.max(0) as usize) % available.len();
    let next_index = ((current_index + 1) % available.len()) as i32;
    Some((available[current_index].clone(), next_index))
}

pub(crate) fn next_cli_account_after(
    accounts: &[MainChatCLIAccountSnapshot],
    provider: &str,
    current_account_id: &str,
    now: f64,
) -> Option<MainChatCLIAccountSnapshot> {
    let available = available_cli_accounts(accounts, provider, now);
    if available.is_empty() {
        return None;
    }
    if let Some(index) = available.iter().position(|account| account.id == current_account_id) {
        let next_index = (index + 1) % available.len();
        return Some(available[next_index].clone());
    }
    available.into_iter().next()
}

pub(crate) fn next_cli_account(
    config: &app_core_protocol::main_chat_provider::MainChatProviderSessionConfig,
) -> Option<MainChatCLIAccountSnapshot> {
    let provider = match config.backend {
        app_core_protocol::main_chat_provider::MainChatProviderBackend::CodexCli => "codex",
        app_core_protocol::main_chat_provider::MainChatProviderBackend::ClaudeCli => "claude",
        app_core_protocol::main_chat_provider::MainChatProviderBackend::GeminiCli => "gemini",
        _ => return None,
    };
    available_cli_accounts(&config.cli_accounts, provider, 0.0)
        .into_iter()
        .next()
}

fn cooldown_expired(health: &MainChatCLIHealthSnapshot, now: f64) -> bool {
    match health.cooldown_until {
        Some(deadline) => deadline <= now,
        None => true,
    }
}

fn quota_exhausted(quota: &MainChatCLIQuotaSnapshot) -> bool {
    quota.daily_limit_usd == Some(0.0)
        || quota.weekly_limit_usd == Some(0.0)
        || quota.monthly_limit_usd == Some(0.0)
        || quota.daily_token_limit == Some(0)
        || quota.weekly_token_limit == Some(0)
        || quota.monthly_token_limit == Some(0)
}

#[cfg(test)]
mod tests {
    use super::{next_cli_account_after, select_active_cli_account};
    use app_core_protocol::main_chat_provider::{
        MainChatCLIAccountSnapshot, MainChatCLIHealthSnapshot, MainChatCLIQuotaSnapshot,
    };
    use std::collections::BTreeMap;

    #[test]
    fn select_active_cli_account_respects_round_robin_and_current_selection() {
        let accounts = vec![account("a", 0), account("b", 1)];
        let (first, next) = select_active_cli_account(&accounts, "codex", 0, None, 1.0).expect("first");
        assert_eq!(first.id, "a");
        assert_eq!(next, 1);

        let (same, unchanged) =
            select_active_cli_account(&accounts, "codex", next, Some("a"), 1.0).expect("same");
        assert_eq!(same.id, "a");
        assert_eq!(unchanged, 1);
    }

    #[test]
    fn next_cli_account_after_skips_to_next_available() {
        let accounts = vec![account("a", 0), account("b", 1)];
        let next = next_cli_account_after(&accounts, "codex", "a", 1.0).expect("next");
        assert_eq!(next.id, "b");
    }

    fn account(id: &str, priority: i32) -> MainChatCLIAccountSnapshot {
        MainChatCLIAccountSnapshot {
            id: id.to_string(),
            provider: "codex".to_string(),
            label: id.to_string(),
            is_enabled: true,
            is_authenticated: true,
            priority,
            profile_path: "/tmp".to_string(),
            env_overrides: BTreeMap::new(),
            quota: MainChatCLIQuotaSnapshot::default(),
            health: MainChatCLIHealthSnapshot::default(),
            created_at: Some(priority as f64),
            updated_at: None,
        }
    }
}
