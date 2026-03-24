use super::openai;
use app_core_protocol::main_chat_provider::MainChatProviderSessionConfig;

pub(crate) fn run(session_id: &str, config: &MainChatProviderSessionConfig) -> Result<(), String> {
    let mut google_config = config.clone();
    if google_config
        .base_url
        .as_deref()
        .unwrap_or_default()
        .trim()
        .is_empty()
    {
        google_config.base_url = Some(
            "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions".to_string(),
        );
    }
    openai::run(session_id, &google_config)
}
