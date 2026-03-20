use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CLIAccountRoutingQuotaSnapshot {
    pub daily_limit_usd: Option<f64>,
    pub weekly_limit_usd: Option<f64>,
    pub monthly_limit_usd: Option<f64>,
    pub daily_token_limit: Option<i64>,
    pub weekly_token_limit: Option<i64>,
    pub monthly_token_limit: Option<i64>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CLIAccountRoutingHealthSnapshot {
    pub cooldown_until: Option<f64>,
    pub last_error_code: Option<String>,
    #[serde(default)]
    pub consecutive_failures: i32,
    #[serde(default)]
    pub is_exhausted_locally: bool,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CLIAccountRoutingAccountSnapshot {
    pub id: String,
    pub provider: String,
    pub label: String,
    #[serde(default)]
    pub is_enabled: bool,
    #[serde(default)]
    pub is_authenticated: bool,
    #[serde(default)]
    pub priority: i32,
    pub profile_path: String,
    pub quota: CLIAccountRoutingQuotaSnapshot,
    pub health: CLIAccountRoutingHealthSnapshot,
    pub created_at: Option<f64>,
    pub updated_at: Option<f64>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CLIAccountUsageTotalsSnapshot {
    pub account_id: String,
    #[serde(default)]
    pub day_cost: f64,
    #[serde(default)]
    pub week_cost: f64,
    #[serde(default)]
    pub month_cost: f64,
    #[serde(default)]
    pub day_tokens: i64,
    #[serde(default)]
    pub week_tokens: i64,
    #[serde(default)]
    pub month_tokens: i64,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CLIAccountRoutingState {
    #[serde(default)]
    pub round_robin_index: BTreeMap<String, i32>,
    #[serde(default)]
    pub current_active_account_by_provider: BTreeMap<String, String>,
    #[serde(default)]
    pub last_failover_reason_by_provider: BTreeMap<String, String>,
    #[serde(default)]
    pub last_switch_at_by_provider: BTreeMap<String, f64>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CLIAccountRoutingFailure {
    #[serde(default)]
    pub is_quota_exhaustion: bool,
    #[serde(default)]
    pub is_rate_limited: bool,
    pub retry_after_seconds: Option<i32>,
    pub normalized_code: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CLIAccountRoutingRequest {
    pub schema_version: i32,
    pub action: String,
    pub state: CLIAccountRoutingState,
    #[serde(default)]
    pub accounts: Vec<CLIAccountRoutingAccountSnapshot>,
    #[serde(default)]
    pub usage_totals: Vec<CLIAccountUsageTotalsSnapshot>,
    pub provider: Option<String>,
    pub account_id: Option<String>,
    pub preferred_active_account_id: Option<String>,
    pub timestamp: Option<f64>,
    pub failure: Option<CLIAccountRoutingFailure>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CLIAccountRoutingError {
    pub code: String,
    pub message: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CLIAccountRoutingResponse {
    pub schema_version: i32,
    pub error: Option<CLIAccountRoutingError>,
    pub state: Option<CLIAccountRoutingState>,
    pub selected_account_id: Option<String>,
    pub active_account_id: Option<String>,
    pub availability_status: Option<String>,
    pub availability_reason: Option<String>,
    pub updated_account: Option<CLIAccountRoutingAccountSnapshot>,
}

impl CLIAccountRoutingResponse {
    pub fn success(state: CLIAccountRoutingState) -> Self {
        Self {
            schema_version: 1,
            error: None,
            state: Some(state),
            selected_account_id: None,
            active_account_id: None,
            availability_status: None,
            availability_reason: None,
            updated_account: None,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(CLIAccountRoutingError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            state: None,
            selected_account_id: None,
            active_account_id: None,
            availability_status: None,
            availability_reason: None,
            updated_account: None,
        }
    }
}
