use app_core_protocol::main_chat_provider::{MainChatCLIAccountSnapshot, MainChatCLIQuotaSnapshot};

pub fn exceeds_policy(
    account: &MainChatCLIAccountSnapshot,
    input_tokens: i64,
    output_tokens: i64,
) -> bool {
    let total = input_tokens + output_tokens;
    exceeds_token_limit(&account.quota, total)
}

fn exceeds_token_limit(quota: &MainChatCLIQuotaSnapshot, total_tokens: i64) -> bool {
    quota
        .daily_token_limit
        .map(|limit| total_tokens >= limit)
        .unwrap_or(false)
        || quota
            .weekly_token_limit
            .map(|limit| total_tokens >= limit)
            .unwrap_or(false)
        || quota
            .monthly_token_limit
            .map(|limit| total_tokens >= limit)
            .unwrap_or(false)
}
