use super::actions::handle_action;
use app_core_protocol::cli_account_routing::*;

#[test]
fn selected_or_next_available_respects_current_active() {
    let response = handle_action(CLIAccountRoutingRequest {
        schema_version: 1,
        action: "selected_or_next_available".to_string(),
        state: CLIAccountRoutingState {
            current_active_account_by_provider: [("codex".to_string(), "a".to_string())].into_iter().collect(),
            ..Default::default()
        },
        accounts: vec![account("a", true), account("b", true)],
        usage_totals: vec![],
        provider: Some("codex".to_string()),
        ..Default::default()
    });
    assert_eq!(response.selected_account_id.as_deref(), Some("a"));
}

#[test]
fn mark_provider_error_sets_cooldown_and_reason() {
    let response = handle_action(CLIAccountRoutingRequest {
        schema_version: 1,
        action: "mark_provider_error".to_string(),
        state: CLIAccountRoutingState::default(),
        accounts: vec![account("a", true)],
        provider: Some("codex".to_string()),
        account_id: Some("a".to_string()),
        timestamp: Some(100.0),
        failure: Some(CLIAccountRoutingFailure {
            is_rate_limited: true,
            retry_after_seconds: Some(10),
            normalized_code: "rate_limited".to_string(),
            ..Default::default()
        }),
        ..Default::default()
    });
    assert_eq!(response.updated_account.as_ref().and_then(|item| item.health.last_error_code.as_deref()), Some("rate_limited"));
    assert_eq!(response.state.as_ref().and_then(|item| item.last_failover_reason_by_provider.get("codex").map(String::as_str)), Some("rate_limited"));
}

#[test]
fn mark_usage_exhausts_account_when_quota_reached() {
    let response = handle_action(CLIAccountRoutingRequest {
        schema_version: 1,
        action: "mark_usage".to_string(),
        state: CLIAccountRoutingState::default(),
        accounts: vec![account("a", true)],
        usage_totals: vec![CLIAccountUsageTotalsSnapshot {
            account_id: "a".to_string(),
            day_cost: 10.0,
            ..Default::default()
        }],
        account_id: Some("a".to_string()),
        ..Default::default()
    });
    assert_eq!(response.updated_account.as_ref().map(|item| item.health.is_exhausted_locally), Some(true));
}

#[test]
fn bootstrap_selections_prefers_authenticated_account_and_preserves_valid_active() {
    let response = handle_action(CLIAccountRoutingRequest {
        schema_version: 1,
        action: "bootstrap_selections".to_string(),
        state: CLIAccountRoutingState {
            current_active_account_by_provider: [("claude".to_string(), "c1".to_string())].into_iter().collect(),
            ..Default::default()
        },
        accounts: vec![
            account_for_provider("a", "codex", false),
            account_for_provider("b", "codex", true),
            account_for_provider("c1", "claude", true),
            account_for_provider("c2", "claude", false),
        ],
        usage_totals: vec![],
        ..Default::default()
    });

    let state = response.state.expect("state");
    assert_eq!(state.current_active_account_by_provider.get("codex").map(String::as_str), Some("b"));
    assert_eq!(state.current_active_account_by_provider.get("claude").map(String::as_str), Some("c1"));
}

#[test]
fn select_account_rotates_round_robin_and_records_active_selection() {
    let response = handle_action(CLIAccountRoutingRequest {
        schema_version: 1,
        action: "select_account".to_string(),
        state: CLIAccountRoutingState {
            round_robin_index: [("codex".to_string(), 1)].into_iter().collect(),
            ..Default::default()
        },
        accounts: vec![account("a", true), account("b", true)],
        usage_totals: vec![],
        provider: Some("codex".to_string()),
        timestamp: Some(33.0),
        ..Default::default()
    });

    assert_eq!(response.selected_account_id.as_deref(), Some("b"));
    let state = response.state.expect("state");
    assert_eq!(state.round_robin_index.get("codex"), Some(&0));
    assert_eq!(state.current_active_account_by_provider.get("codex").map(String::as_str), Some("b"));
    assert_eq!(state.last_switch_at_by_provider.get("codex"), Some(&33.0));
}

#[test]
fn next_available_account_wraps_and_keeps_failover_reason() {
    let response = handle_action(CLIAccountRoutingRequest {
        schema_version: 1,
        action: "next_available_account_after".to_string(),
        state: CLIAccountRoutingState::default(),
        accounts: vec![account("a", true), account("b", true)],
        usage_totals: vec![],
        provider: Some("codex".to_string()),
        account_id: Some("b".to_string()),
        timestamp: Some(44.0),
        failure: Some(CLIAccountRoutingFailure {
            normalized_code: "rate_limited".to_string(),
            ..Default::default()
        }),
        ..Default::default()
    });

    assert_eq!(response.selected_account_id.as_deref(), Some("a"));
    let state = response.state.expect("state");
    assert_eq!(state.current_active_account_by_provider.get("codex").map(String::as_str), Some("a"));
    assert_eq!(state.last_failover_reason_by_provider.get("codex").map(String::as_str), Some("rate_limited"));
}

#[test]
fn current_availability_and_active_account_reflect_state() {
    let accounts = vec![account("a", true), account("b", false)];
    let active_response = handle_action(CLIAccountRoutingRequest {
        schema_version: 1,
        action: "active_account".to_string(),
        state: CLIAccountRoutingState {
            current_active_account_by_provider: [("codex".to_string(), "a".to_string())].into_iter().collect(),
            ..Default::default()
        },
        accounts: accounts.clone(),
        provider: Some("codex".to_string()),
        ..Default::default()
    });
    assert_eq!(active_response.active_account_id.as_deref(), Some("a"));

    let unavailable = handle_action(CLIAccountRoutingRequest {
        schema_version: 1,
        action: "current_availability".to_string(),
        state: CLIAccountRoutingState::default(),
        accounts: vec![CLIAccountRoutingAccountSnapshot {
            health: CLIAccountRoutingHealthSnapshot {
                is_exhausted_locally: true,
                ..Default::default()
            },
            ..account("blocked", true)
        }],
        usage_totals: vec![],
        provider: Some("codex".to_string()),
        ..Default::default()
    });
    assert_eq!(unavailable.availability_status.as_deref(), Some("all_exhausted"));
}

fn account(id: &str, authenticated: bool) -> CLIAccountRoutingAccountSnapshot {
    account_for_provider(id, "codex", authenticated)
}

fn account_for_provider(id: &str, provider: &str, authenticated: bool) -> CLIAccountRoutingAccountSnapshot {
    CLIAccountRoutingAccountSnapshot {
        id: id.to_string(),
        provider: provider.to_string(),
        label: id.to_string(),
        is_enabled: true,
        is_authenticated: authenticated,
        priority: 0,
        profile_path: "/tmp".to_string(),
        quota: CLIAccountRoutingQuotaSnapshot {
            daily_limit_usd: Some(10.0),
            ..Default::default()
        },
        health: CLIAccountRoutingHealthSnapshot::default(),
        created_at: Some(1.0),
        updated_at: None,
    }
}
