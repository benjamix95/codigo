use super::availability::{
    available_accounts, exceeds_policy, sorted_provider_accounts, usage_by_account,
};
use app_core_protocol::cli_account_routing::{
    CLIAccountRoutingAccountSnapshot, CLIAccountRoutingRequest, CLIAccountRoutingResponse,
    CLIAccountRoutingState, CLIAccountUsageTotalsSnapshot,
};
use std::collections::BTreeMap;

pub fn handle_action(request: CLIAccountRoutingRequest) -> CLIAccountRoutingResponse {
    if request.schema_version != 1 {
        return CLIAccountRoutingResponse::error("unsupported_schema", "schemaVersion must be 1");
    }

    let usage = usage_by_account(&request.usage_totals);
    match request.action.as_str() {
        "bootstrap_selections" => bootstrap_selections(request.state, &request.accounts),
        "select_account" => select_account(request, &usage),
        "selected_or_next_available" => selected_or_next_available(request, &usage),
        "next_available_account_after" => next_available_account_after(request, &usage),
        "current_availability" => current_availability(request, &usage),
        "active_account" => active_account(request),
        "mark_usage" => mark_usage(request, &usage),
        "mark_provider_error" => mark_provider_error(request),
        "mark_account_selected" => mark_account_selected(request),
        _ => CLIAccountRoutingResponse::error(
            "unsupported_action",
            "account routing action not supported",
        ),
    }
}

fn bootstrap_selections(
    mut state: CLIAccountRoutingState,
    accounts: &[CLIAccountRoutingAccountSnapshot],
) -> CLIAccountRoutingResponse {
    for provider in ["codex", "claude", "gemini"] {
        let enabled = sorted_provider_accounts(accounts, provider, false);
        if enabled.is_empty() {
            continue;
        }
        if let Some(current) = state.current_active_account_by_provider.get(provider) {
            if enabled.iter().any(|account| account.id == *current) {
                continue;
            }
        }
        if let Some(selected) = enabled
            .iter()
            .find(|account| account.is_authenticated)
            .or_else(|| enabled.first())
        {
            state
                .current_active_account_by_provider
                .insert(provider.to_string(), selected.id.clone());
        }
    }
    CLIAccountRoutingResponse::success(state)
}

fn select_account(
    request: CLIAccountRoutingRequest,
    usage: &BTreeMap<String, CLIAccountUsageTotalsSnapshot>,
) -> CLIAccountRoutingResponse {
    let mut state = request.state;
    let Some(provider) = request.provider else {
        return CLIAccountRoutingResponse::error("missing_provider", "provider is required");
    };
    let available = available_accounts(&request.accounts, &provider, usage, true);
    if available.is_empty() {
        return unavailable(state);
    }
    let current = state
        .round_robin_index
        .get(&provider)
        .copied()
        .unwrap_or(0)
        .max(0) as usize;
    let index = current % available.len();
    let selected = available[index].clone();
    state
        .round_robin_index
        .insert(provider.clone(), ((index + 1) % available.len()) as i32);
    select_into_state(&mut state, &provider, &selected.id, request.timestamp, None);
    let mut response = CLIAccountRoutingResponse::success(state);
    response.selected_account_id = Some(selected.id);
    response.availability_status = Some("available".to_string());
    response
}

fn selected_or_next_available(
    request: CLIAccountRoutingRequest,
    usage: &BTreeMap<String, CLIAccountUsageTotalsSnapshot>,
) -> CLIAccountRoutingResponse {
    let state = request.state.clone();
    let Some(provider) = request.provider.clone() else {
        return CLIAccountRoutingResponse::error("missing_provider", "provider is required");
    };
    let available = available_accounts(&request.accounts, &provider, usage, true);
    if available.is_empty() {
        return unavailable(state);
    }
    if let Some(active) = state.current_active_account_by_provider.get(&provider) {
        if let Some(found) = available.iter().find(|account| account.id == *active) {
            let mut response = CLIAccountRoutingResponse::success(state);
            response.selected_account_id = Some(found.id.clone());
            response.availability_status = Some("available".to_string());
            return response;
        }
    }
    select_account(request, usage)
}

fn next_available_account_after(
    request: CLIAccountRoutingRequest,
    usage: &BTreeMap<String, CLIAccountUsageTotalsSnapshot>,
) -> CLIAccountRoutingResponse {
    let mut state = request.state;
    let Some(provider) = request.provider.clone() else {
        return CLIAccountRoutingResponse::error("missing_provider", "provider is required");
    };
    let Some(current_id) = request.account_id.clone() else {
        return CLIAccountRoutingResponse::error("missing_account_id", "accountId is required");
    };
    let available = available_accounts(&request.accounts, &provider, usage, true);
    if available.is_empty() {
        return unavailable(state);
    }
    let selected = if let Some(index) = available
        .iter()
        .position(|account| account.id == current_id)
    {
        available[(index + 1) % available.len()].clone()
    } else {
        available[0].clone()
    };
    select_into_state(
        &mut state,
        &provider,
        &selected.id,
        request.timestamp,
        request.failure.map(|it| it.normalized_code),
    );
    let mut response = CLIAccountRoutingResponse::success(state);
    response.selected_account_id = Some(selected.id);
    response.availability_status = Some("available".to_string());
    response
}

fn current_availability(
    request: CLIAccountRoutingRequest,
    usage: &BTreeMap<String, CLIAccountUsageTotalsSnapshot>,
) -> CLIAccountRoutingResponse {
    let state = request.state;
    let Some(provider) = request.provider else {
        return CLIAccountRoutingResponse::error("missing_provider", "provider is required");
    };
    if available_accounts(&request.accounts, &provider, usage, true).is_empty() {
        return unavailable(state);
    }
    let mut response = CLIAccountRoutingResponse::success(state);
    response.availability_status = Some("available".to_string());
    response
}

fn active_account(request: CLIAccountRoutingRequest) -> CLIAccountRoutingResponse {
    let state = request.state;
    let Some(provider) = request.provider else {
        return CLIAccountRoutingResponse::error("missing_provider", "provider is required");
    };
    let mut response = CLIAccountRoutingResponse::success(state.clone());
    response.active_account_id = state
        .current_active_account_by_provider
        .get(&provider)
        .cloned();
    response
}

fn mark_usage(
    request: CLIAccountRoutingRequest,
    usage: &BTreeMap<String, CLIAccountUsageTotalsSnapshot>,
) -> CLIAccountRoutingResponse {
    let Some(account_id) = request.account_id else {
        return CLIAccountRoutingResponse::error("missing_account_id", "accountId is required");
    };
    let Some(mut account) = request
        .accounts
        .iter()
        .find(|item| item.id == account_id)
        .cloned()
    else {
        return CLIAccountRoutingResponse::error("missing_account", "account not found");
    };
    account.health.consecutive_failures = 0;
    account.health.last_error_code = None;
    account.health.cooldown_until = None;
    account.health.is_exhausted_locally = usage
        .get(&account.id)
        .map(|totals| exceeds_policy(&account, totals))
        .unwrap_or(account.health.is_exhausted_locally);
    if account.health.is_exhausted_locally {
        account.health.last_error_code = Some("local_limit_reached".to_string());
    }
    let mut response = CLIAccountRoutingResponse::success(request.state);
    response.updated_account = Some(account);
    response
}

fn mark_provider_error(request: CLIAccountRoutingRequest) -> CLIAccountRoutingResponse {
    let mut state = request.state;
    let Some(account_id) = request.account_id else {
        return CLIAccountRoutingResponse::error("missing_account_id", "accountId is required");
    };
    let Some(failure) = request.failure else {
        return CLIAccountRoutingResponse::error("missing_failure", "failure is required");
    };
    let Some(provider) = request.provider else {
        return CLIAccountRoutingResponse::error("missing_provider", "provider is required");
    };
    let Some(mut account) = request
        .accounts
        .iter()
        .find(|item| item.id == account_id)
        .cloned()
    else {
        return CLIAccountRoutingResponse::error("missing_account", "account not found");
    };
    account.health.consecutive_failures += 1;
    account.health.last_error_code = Some(failure.normalized_code.clone());
    if failure.is_quota_exhaustion {
        account.health.is_exhausted_locally = true;
    }
    if failure.is_rate_limited {
        let retry_after = failure.retry_after_seconds.unwrap_or(120).max(30) as f64;
        account.health.cooldown_until = request.timestamp.map(|timestamp| timestamp + retry_after);
    }
    state
        .last_failover_reason_by_provider
        .insert(provider, failure.normalized_code);
    let mut response = CLIAccountRoutingResponse::success(state);
    response.updated_account = Some(account);
    response
}

fn mark_account_selected(request: CLIAccountRoutingRequest) -> CLIAccountRoutingResponse {
    let mut state = request.state;
    let Some(provider) = request.provider else {
        return CLIAccountRoutingResponse::error("missing_provider", "provider is required");
    };
    let Some(account_id) = request.account_id else {
        return CLIAccountRoutingResponse::error("missing_account_id", "accountId is required");
    };
    select_into_state(
        &mut state,
        &provider,
        &account_id,
        request.timestamp,
        request.failure.map(|it| it.normalized_code),
    );
    CLIAccountRoutingResponse::success(state)
}

fn unavailable(state: CLIAccountRoutingState) -> CLIAccountRoutingResponse {
    let mut response = CLIAccountRoutingResponse::success(state);
    response.availability_status = Some("all_exhausted".to_string());
    response.availability_reason = Some("No available account".to_string());
    response
}

fn select_into_state(
    state: &mut CLIAccountRoutingState,
    provider: &str,
    account_id: &str,
    timestamp: Option<f64>,
    reason: Option<String>,
) {
    state
        .current_active_account_by_provider
        .insert(provider.to_string(), account_id.to_string());
    if let Some(timestamp) = timestamp {
        state
            .last_switch_at_by_provider
            .insert(provider.to_string(), timestamp);
    }
    if let Some(reason) = reason {
        state
            .last_failover_reason_by_provider
            .insert(provider.to_string(), reason);
    }
}
