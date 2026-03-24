use app_core_protocol::cli_account_routing::{
    CLIAccountRoutingAccountSnapshot, CLIAccountUsageTotalsSnapshot,
};
use std::collections::BTreeMap;

pub(crate) fn available_accounts(
    accounts: &[CLIAccountRoutingAccountSnapshot],
    provider: &str,
    usage: &BTreeMap<String, CLIAccountUsageTotalsSnapshot>,
    require_auth: bool,
) -> Vec<CLIAccountRoutingAccountSnapshot> {
    let mut items = sorted_provider_accounts(accounts, provider, require_auth);
    items.retain(|account| !account.health.is_exhausted_locally);
    items.retain(|account| {
        account
            .health
            .cooldown_until
            .map(|value| value <= now())
            .unwrap_or(true)
    });
    items.retain(|account| {
        usage
            .get(&account.id)
            .map(|totals| !exceeds_policy(account, totals))
            .unwrap_or(true)
    });
    items
}

pub(crate) fn sorted_provider_accounts(
    accounts: &[CLIAccountRoutingAccountSnapshot],
    provider: &str,
    require_auth: bool,
) -> Vec<CLIAccountRoutingAccountSnapshot> {
    let mut items = accounts
        .iter()
        .filter(|account| account.provider == provider)
        .filter(|account| account.is_enabled)
        .filter(|account| !require_auth || account.is_authenticated)
        .cloned()
        .collect::<Vec<_>>();
    items.sort_by(|lhs, rhs| {
        lhs.priority
            .cmp(&rhs.priority)
            .then_with(|| {
                lhs.created_at
                    .partial_cmp(&rhs.created_at)
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
            .then_with(|| lhs.id.cmp(&rhs.id))
    });
    items
}

pub(crate) fn exceeds_policy(
    account: &CLIAccountRoutingAccountSnapshot,
    usage: &CLIAccountUsageTotalsSnapshot,
) -> bool {
    account
        .quota
        .daily_limit_usd
        .map(|value| usage.day_cost >= value)
        .unwrap_or(false)
        || account
            .quota
            .weekly_limit_usd
            .map(|value| usage.week_cost >= value)
            .unwrap_or(false)
        || account
            .quota
            .monthly_limit_usd
            .map(|value| usage.month_cost >= value)
            .unwrap_or(false)
        || account
            .quota
            .daily_token_limit
            .map(|value| usage.day_tokens >= value)
            .unwrap_or(false)
        || account
            .quota
            .weekly_token_limit
            .map(|value| usage.week_tokens >= value)
            .unwrap_or(false)
        || account
            .quota
            .monthly_token_limit
            .map(|value| usage.month_tokens >= value)
            .unwrap_or(false)
}

pub(crate) fn usage_by_account(
    items: &[CLIAccountUsageTotalsSnapshot],
) -> BTreeMap<String, CLIAccountUsageTotalsSnapshot> {
    items
        .iter()
        .map(|item| (item.account_id.clone(), item.clone()))
        .collect()
}

pub(crate) fn now() -> f64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|value| value.as_secs_f64())
        .unwrap_or(0.0)
}
