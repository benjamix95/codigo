use crate::main_chat::state::{ensure_direct_stream_defaults, reset_output};
use app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot;

pub fn prepare_auto_continuation(
    mut snapshot: MainChatRuntimeSnapshot,
    original_prompt: &str,
    current_text: &str,
) -> MainChatRuntimeSnapshot {
    ensure_direct_stream_defaults(&mut snapshot);
    reset_output(&mut snapshot);
    if should_auto_continue_stub(current_text) {
        if let Some(output) = snapshot.output.as_mut() {
            output.follow_up_prompt = Some(format!(
                "Immediately continue your previous response and complete the task to a concrete outcome.\nExecute needed steps autonomously (analyze, act, verify, fix if needed) and do not stop at intentions.\n\nOriginal request:\n{original_prompt}\n\nText already sent:\n{current_text}"
            ));
        }
    }
    snapshot
}

pub fn should_auto_continue_stub(text: &str) -> bool {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return false;
    }
    if trimmed.split_whitespace().count() > 260 {
        return false;
    }
    let low = trimmed.to_lowercase();
    let stub_signals = [
        "i'll start",
        "i will start",
        "i'll begin",
        "i will begin",
        "first, i'll",
        "first i will",
        "let me start",
        "let me begin",
        "let me check",
        "i can continue",
        "would you like me to",
        "if you want i can",
        "next i'll",
        "next i will",
    ];
    stub_signals.iter().any(|signal| low.contains(signal))
        || low.ends_with("...")
        || low.ends_with(':')
}

#[cfg(test)]
mod tests {
    use super::{prepare_auto_continuation, should_auto_continue_stub};
    use app_core_protocol::main_chat::MainChatTurnState;
    use app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot;

    #[test]
    fn detects_stub_and_builds_follow_up_prompt() {
        let snapshot = prepare_auto_continuation(base_snapshot(), "Fix it", "I'll start by checking the files...");
        assert!(should_auto_continue_stub("I'll start by checking the files..."));
        assert!(snapshot.output.and_then(|it| it.follow_up_prompt).is_some());
    }

    fn base_snapshot() -> MainChatRuntimeSnapshot {
        MainChatRuntimeSnapshot {
            turn_state: MainChatTurnState {
                conversation_id: "conv".to_string(),
                assistant_message_id: "msg".to_string(),
                turn_id: "turn".to_string(),
                status: "idle".to_string(),
                ..Default::default()
            },
            ..Default::default()
        }
    }
}
