use super::process::stream_process_lines;
use crate::main_chat::providers::common::{flatten_string_map, join_cli_prompt, string_value};
use crate::main_chat::providers::parsing::jsonl::parse_jsonl_line;
use crate::main_chat::providers::session::{
    emit_error, emit_raw, emit_text_delta, failover_to_next_cli_account, is_cancelled, running_cli_account,
};
use app_core_protocol::main_chat_provider::MainChatProviderSessionConfig;
use std::collections::BTreeMap;

pub(crate) fn run(session_id: &str, config: &MainChatProviderSessionConfig) -> Result<(), String> {
    let account = running_cli_account(session_id, config, "claude")?;
    let executable = account
        .as_ref()
        .and_then(|item| item.env_overrides.get("CLAUDE_PATH").cloned())
        .or_else(|| config.claude_path.clone())
        .ok_or_else(|| "missing_claude_path".to_string())?;
    let prompt = join_cli_prompt(
        config.system_prompt.as_deref(),
        &config.prompt,
        config.context_prompt.as_deref(),
        &config.attachments,
    );
    let mut args = vec![
        "-p".to_string(),
        prompt,
        "--output-format".to_string(),
        "stream-json".to_string(),
        "--verbose".to_string(),
    ];
    if let Some(model) = config.claude_model.clone().filter(|value| !value.trim().is_empty()) {
        args.extend(["--model".to_string(), model]);
    }
    // If a coderide MCP server binary is available, write a temp config
    // so Claude CLI can call our custom tools (todo, plan, debug, etc.).
    // We also block built-in tools that have MCP equivalents so Claude
    // is forced to use the coderide MCP versions (which integrate with
    // the IDE: todo tracking, plan state, debug mode, etc.).
    let mcp_config_path = write_mcp_config(config);
    if let Some(ref path) = mcp_config_path {
        args.extend(["--mcp-config".to_string(), path.clone()]);
        // Block built-in tools that overlap with coderide MCP tools.
        // Claude will discover and use the MCP equivalents instead.
        args.extend([
            "--disallowedTools".to_string(),
            "Read,Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch,NotebookEdit,TodoWrite".to_string(),
        ]);
        eprintln!("[CLAUDE_DEBUG] MCP config written to: {}", path);
        eprintln!("[CLAUDE_DEBUG] Built-in tools blocked in favor of MCP coderide tools");
    } else {
        eprintln!("[CLAUDE_DEBUG] MCP config NOT available (server_path={:?})", config.claude_mcp_server_path);
        if !config.claude_allowed_tools.is_empty() {
            // Fallback: restrict to built-in tool whitelist when MCP is unavailable
            args.extend([
                "--allowedTools".to_string(),
                config.claude_allowed_tools.join(","),
            ]);
        }
    }

    // Log the full command for debugging
    eprintln!("[CLAUDE_DEBUG] executable={}", executable);
    eprintln!("[CLAUDE_DEBUG] args (excluding prompt): {:?}",
        args.iter().enumerate().filter(|(i, _)| *i != 1).map(|(_, a)| a.clone()).collect::<Vec<_>>());
    eprintln!("[CLAUDE_DEBUG] workspace={}", config.workspace_path);

    let mut environment = std::env::vars().collect::<BTreeMap<_, _>>();
    if let Some(account) = account {
        environment.extend(account.env_overrides);
    }
    // Track whether we received text via streaming deltas so we can
    // skip the redundant `result` event that would duplicate content.
    let mut received_stream_text = false;
    // Track whether we received reasoning via streaming so the final
    // message.content thinking blocks don't duplicate it.
    let mut received_stream_reasoning = false;
    // Track whether turn_started has been emitted so we emit it
    // exactly once before the first meaningful event.
    let mut emitted_turn_started = false;
    // Counter for logging
    let mut line_count: u64 = 0;

    stream_process_lines(
        &executable,
        &args,
        &config.workspace_path,
        &environment,
        |line| {
            line_count += 1;
            consume_line(
                session_id,
                line,
                &mut received_stream_text,
                &mut received_stream_reasoning,
                &mut emitted_turn_started,
                line_count,
            )
        },
        || is_cancelled(session_id),
    )
}

fn consume_line(
    session_id: &str,
    line: &str,
    received_stream_text: &mut bool,
    received_stream_reasoning: &mut bool,
    emitted_turn_started: &mut bool,
    line_number: u64,
) -> Result<(), String> {
    // Log every raw line (truncated for readability, respecting char boundaries)
    let truncated = if line.len() > 300 {
        let mut end = 300;
        while end > 0 && !line.is_char_boundary(end) { end -= 1; }
        &line[..end]
    } else {
        line
    };
    eprintln!("[CLAUDE_DEBUG] line#{}: {}", line_number, truncated);

    let payloads = parse_jsonl_line(line);
    eprintln!("[CLAUDE_DEBUG] line#{}: parsed {} JSON payloads", line_number, payloads.len());

    for (idx, json) in payloads.iter().enumerate() {
        // Log the top-level keys and type
        let top_keys: Vec<String> = json.as_object()
            .map(|o| o.keys().cloned().collect())
            .unwrap_or_default();
        let event_type = string_value(&json["type"]).unwrap_or_else(|| "(no type)".to_string());
        eprintln!("[CLAUDE_DEBUG] line#{} payload#{}: type={}, keys={:?}",
            line_number, idx, event_type, top_keys);

        // Emit turn_started before the first meaningful event so the
        // Swift layer can create auto-todo placeholders and initialize
        // tool trace turns before any tool events arrive.
        if !*emitted_turn_started {
            *emitted_turn_started = true;
            eprintln!("[CLAUDE_DEBUG] >>> EMITTING turn_started");
            emit_raw(session_id, "turn_started", BTreeMap::new());
        }
        if let Some(usage) = json.get("usage").and_then(|value| value.as_object()) {
            let mut payload = BTreeMap::new();
            if let Some(value) = usage
                .get("input_tokens")
                .or_else(|| usage.get("prompt_tokens"))
                .and_then(string_value)
            {
                payload.insert("input_tokens".to_string(), value);
            }
            if let Some(value) = usage
                .get("output_tokens")
                .or_else(|| usage.get("completion_tokens"))
                .and_then(string_value)
            {
                payload.insert("output_tokens".to_string(), value);
            }
            payload.insert("model".to_string(), "claude-cli".to_string());
            if payload.contains_key("input_tokens") && payload.contains_key("output_tokens") {
                eprintln!("[CLAUDE_DEBUG] >>> EMITTING usage: {:?}", payload);
                emit_raw(session_id, "usage", payload);
            }
        }
        if event_type == "result" {
            eprintln!("[CLAUDE_DEBUG] GOT result event. received_stream_text={}", *received_stream_text);
            if let Some(result_text) = string_value(&json["result"]) {
                eprintln!("[CLAUDE_DEBUG] result text length={}", result_text.len());
            }
            // Skip result text when streaming already provided it —
            // the result event contains the full combined text
            // (reasoning + response) which would duplicate content.
            if !*received_stream_text {
                if let Some(result) = string_value(&json["result"]) {
                    eprintln!("[CLAUDE_DEBUG] >>> EMITTING text_delta from result (len={})", result.len());
                    emit_text_delta(session_id, &result);
                }
            } else {
                eprintln!("[CLAUDE_DEBUG] SKIPPING result text (already streamed)");
            }
            continue;
        }
        if event_type == "stream_event" {
            // Log the full event structure for debugging
            if let Some(event_obj) = json.get("event") {
                let event_type_inner = event_obj.get("type").and_then(|v| v.as_str()).unwrap_or("?");
                eprintln!("[CLAUDE_DEBUG] stream_event inner type={}", event_type_inner);

                if let Some(delta) = event_obj.get("delta").and_then(|value| value.as_object()) {
                    let delta_type = delta.get("type").and_then(string_value)
                        .unwrap_or_else(|| "(no delta type)".to_string());
                    eprintln!("[CLAUDE_DEBUG] delta type={}", delta_type);

                    if delta_type == "thinking_delta" {
                        if let Some(thinking) = delta.get("thinking").and_then(string_value) {
                            *received_stream_reasoning = true;
                            eprintln!("[CLAUDE_DEBUG] >>> EMITTING reasoning delta (len={})", thinking.len());
                            emit_raw(
                                session_id,
                                "reasoning",
                                BTreeMap::from([
                                    ("output".to_string(), thinking),
                                    ("title".to_string(), "Reasoning".to_string()),
                                    ("group_id".to_string(), "reasoning-stream".to_string()),
                                ]),
                            );
                        } else {
                            eprintln!("[CLAUDE_DEBUG] thinking_delta but no 'thinking' field!");
                        }
                    }
                    if delta_type == "text_delta" {
                        if let Some(text) = delta.get("text").and_then(string_value) {
                            *received_stream_text = true;
                            eprintln!("[CLAUDE_DEBUG] >>> EMITTING text_delta (len={})", text.len());
                            emit_text_delta(session_id, &text);
                        } else {
                            eprintln!("[CLAUDE_DEBUG] text_delta but no 'text' field!");
                        }
                    }
                    if delta_type != "thinking_delta" && delta_type != "text_delta" {
                        eprintln!("[CLAUDE_DEBUG] UNHANDLED delta type: {}", delta_type);
                        let delta_keys: Vec<String> = delta.keys().cloned().collect();
                        eprintln!("[CLAUDE_DEBUG]   delta keys: {:?}", delta_keys);
                    }
                } else {
                    eprintln!("[CLAUDE_DEBUG] stream_event has no delta object. event keys: {:?}",
                        event_obj.as_object().map(|o| o.keys().cloned().collect::<Vec<_>>()));
                }
            } else {
                eprintln!("[CLAUDE_DEBUG] stream_event but no 'event' field!");
            }
            continue;
        }
        // Check for message.content blocks — only process `assistant` messages.
        // `user` messages contain subagent prompts and tool_result blocks that
        // must NOT be emitted as text_delta (they would pollute the chat).
        let is_assistant_message = event_type == "assistant";
        if let Some(content) = json
            .get("message")
            .and_then(|value| value.get("content"))
            .and_then(|value| value.as_array())
        {
            eprintln!("[CLAUDE_DEBUG] message.content has {} blocks (is_assistant={})", content.len(), is_assistant_message);
            if !is_assistant_message {
                eprintln!("[CLAUDE_DEBUG] SKIPPING non-assistant message content (type={})", event_type);
            }
            for (bi, block) in content.iter().enumerate() {
                let block_type = block.get("type").and_then(string_value)
                    .unwrap_or_else(|| "(no type)".to_string());
                eprintln!("[CLAUDE_DEBUG] message.content[{}] type={}", bi, block_type);

                if block_type == "text" && is_assistant_message {
                    // Skip final message text blocks if streaming already
                    // provided the text — avoids double-appending.
                    if !*received_stream_text {
                        if let Some(text) = block.get("text").and_then(string_value) {
                            eprintln!("[CLAUDE_DEBUG] >>> EMITTING text_delta from message.content (len={})", text.len());
                            emit_text_delta(session_id, &text);
                        }
                    } else {
                        eprintln!("[CLAUDE_DEBUG] SKIPPING message.content text (already streamed)");
                    }
                }
                if block_type == "thinking" && is_assistant_message {
                    // Skip final thinking blocks if streaming already
                    // provided reasoning — avoids duplicate reasoning.
                    if !*received_stream_reasoning {
                        if let Some(thinking) = block
                            .get("thinking")
                            .and_then(string_value)
                            .or_else(|| block.get("text").and_then(string_value))
                        {
                            eprintln!("[CLAUDE_DEBUG] >>> EMITTING reasoning from message.content (len={})", thinking.len());
                            emit_raw(
                                session_id,
                                "reasoning",
                                BTreeMap::from([
                                    ("output".to_string(), thinking),
                                    ("title".to_string(), "Reasoning".to_string()),
                                    ("group_id".to_string(), "reasoning-stream".to_string()),
                                ]),
                            );
                        }
                    } else {
                        eprintln!("[CLAUDE_DEBUG] SKIPPING message.content thinking (already streamed)");
                    }
                }
                if block_type == "tool_use" && is_assistant_message {
                    let name = block.get("name").and_then(string_value).unwrap_or_default();
                    eprintln!("[CLAUDE_DEBUG] >>> EMITTING tool_use name={}", name);
                    let mut payload = flatten_string_map(block);
                    // Merge nested `input` fields into the top-level payload
                    // so tool parameters (command, path, file_path, etc.)
                    // are visible to the Swift event mapper and UI cards.
                    if let Some(input) = block.get("input") {
                        let input_keys: Vec<String> = input.as_object()
                            .map(|o| o.keys().cloned().collect())
                            .unwrap_or_default();
                        eprintln!("[CLAUDE_DEBUG]   tool input keys: {:?}", input_keys);
                        for (k, v) in flatten_string_map(input) {
                            payload.entry(k).or_insert(v);
                        }
                    }
                    let normalized = normalize_tool_name(&name);
                    eprintln!("[CLAUDE_DEBUG]   normalized tool name: {}", normalized);
                    emit_raw(session_id, &normalized, payload);
                }
                if block_type != "text" && block_type != "thinking" && block_type != "tool_use" {
                    eprintln!("[CLAUDE_DEBUG] UNHANDLED message.content block type: {}", block_type);
                }
            }
        }
        // Check for unhandled event types
        if event_type != "result" && event_type != "stream_event" && event_type != "(no type)" {
            eprintln!("[CLAUDE_DEBUG] UNHANDLED top-level event type: {}", event_type);
        }
        // Check for errors
        if let Some(error) = json
            .get("error")
            .and_then(|v| v.as_str())
            .or_else(|| {
                json.get("message")
                    .and_then(|v| v.as_str())
            })
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
        {
            eprintln!("[CLAUDE_DEBUG] ERROR: {}", error);
            if error.to_lowercase().contains("rate limit") || error.to_lowercase().contains("quota") {
                if failover_to_next_cli_account(session_id, "claude", &error)? {
                    return Err("retry_with_next_account".to_string());
                }
            }
            emit_error(session_id, &error);
            return Err(error);
        }
    }
    Ok(())
}

fn normalize_tool_name(name: &str) -> String {
    let lowered = name.trim().to_lowercase();
    match lowered.as_str() {
        "mermaidrender" => "mermaid_render".to_string(),
        "planrequestuserinput" => "plan_request_user_input".to_string(),
        other => other.replace('-', "_"),
    }
}

/// Writes a temporary MCP config JSON so Claude CLI can connect to our
/// coderide MCP server and use its custom tools (todo, plan, debug, etc.).
/// Returns the file path if successful, `None` otherwise.
fn write_mcp_config(config: &MainChatProviderSessionConfig) -> Option<String> {
    let server_path = config.claude_mcp_server_path.as_deref()?.trim();
    if server_path.is_empty() {
        eprintln!("[CLAUDE_DEBUG] write_mcp_config: server_path is empty");
        return None;
    }
    if !std::path::Path::new(server_path).exists() {
        eprintln!("[CLAUDE_DEBUG] write_mcp_config: server_path does not exist: {}", server_path);
        return None;
    }
    eprintln!("[CLAUDE_DEBUG] write_mcp_config: using server at {}", server_path);
    let escaped_path = server_path.replace('\\', "\\\\").replace('"', "\\\"");
    let escaped_workspace = config.workspace_path.replace('\\', "\\\\").replace('"', "\\\"");
    let config_json = format!(
        "{{\n  \"mcpServers\": {{\n    \"coderide\": {{\n      \"command\": \"{}\",\n      \"args\": [],\n      \"env\": {{\n        \"SOLOCODE_WORKSPACE\": \"{}\"\n      }}\n    }}\n  }}\n}}",
        escaped_path,
        escaped_workspace,
    );
    let tmp_dir = std::env::temp_dir().join("solocode-claude-mcp");
    std::fs::create_dir_all(&tmp_dir).ok()?;
    let config_path = tmp_dir.join("mcp-config.json");
    std::fs::write(&config_path, &config_json).ok()?;
    eprintln!("[CLAUDE_DEBUG] write_mcp_config: wrote config to {}", config_path.display());
    eprintln!("[CLAUDE_DEBUG] write_mcp_config: content={}", config_json);
    Some(config_path.to_string_lossy().into_owned())
}
