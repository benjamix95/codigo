use super::process::stream_process_lines;
use crate::main_chat::providers::common::{
    apply_gui_safe_cli_path, flatten_string_map, join_cli_prompt, string_value,
};
use crate::main_chat::providers::parsing::jsonl::parse_jsonl_line;
use crate::main_chat::providers::session::{
    emit_error, emit_raw, emit_text_delta, failover_to_next_cli_account, is_cancelled,
    running_cli_account,
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
    if let Some(model) = config
        .claude_model
        .clone()
        .filter(|value| !value.trim().is_empty())
    {
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
        // In non-interactive (-p) mode, MCP tool permissions are not
        // auto-granted.  bypassPermissions lets Claude use MCP tools
        // without an interactive approval prompt.
        args.extend([
            "--permission-mode".to_string(),
            "bypassPermissions".to_string(),
        ]);
        // Block built-in tools that overlap with coderide MCP tools.
        // Claude will discover and use the MCP equivalents instead.
        // NOTE: Bash is NOT blocked because subagents need it for
        // command execution and there is no full MCP equivalent.
        args.extend([
            "--disallowedTools".to_string(),
            "Read,Edit,Write,Glob,Grep,WebSearch,WebFetch,NotebookEdit,TodoWrite".to_string(),
        ]);
        // Inject coderide workflow instructions so Claude uses the
        // enhanced MCP tools and follows the expected IDE workflow.
        args.extend([
            "--append-system-prompt".to_string(),
            coderide_system_prompt().to_string(),
        ]);
        crate::provider_stderr_eprintln!("[CLAUDE_DEBUG] MCP config written to: {}", path);
        crate::provider_stderr_eprintln!("[CLAUDE_DEBUG] Built-in tools blocked, permission-mode=bypassPermissions, coderide prompt injected");
    } else {
        crate::provider_stderr_eprintln!(
            "[CLAUDE_DEBUG] MCP config NOT available (server_path={:?})",
            config.claude_mcp_server_path
        );
        if !config.claude_allowed_tools.is_empty() {
            // Fallback: restrict to built-in tool whitelist when MCP is unavailable
            args.extend([
                "--allowedTools".to_string(),
                config.claude_allowed_tools.join(","),
            ]);
        }
    }

    // Log the full command for debugging
    crate::provider_stderr_eprintln!("[CLAUDE_DEBUG] executable={}", executable);
    crate::provider_stderr_eprintln!(
        "[CLAUDE_DEBUG] args (excluding prompt): {:?}",
        args.iter()
            .enumerate()
            .filter(|(i, _)| *i != 1)
            .map(|(_, a)| a.clone())
            .collect::<Vec<_>>()
    );
    crate::provider_stderr_eprintln!("[CLAUDE_DEBUG] workspace={}", config.workspace_path);

    let mut environment = std::env::vars().collect::<BTreeMap<_, _>>();
    if let Some(account) = account {
        environment.extend(account.env_overrides);
    }
    apply_gui_safe_cli_path(&mut environment);
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
        while end > 0 && !line.is_char_boundary(end) {
            end -= 1;
        }
        &line[..end]
    } else {
        line
    };
    crate::provider_stderr_eprintln!("[CLAUDE_DEBUG] line#{}: {}", line_number, truncated);

    let payloads = parse_jsonl_line(line);
    crate::provider_stderr_eprintln!(
        "[CLAUDE_DEBUG] line#{}: parsed {} JSON payloads",
        line_number,
        payloads.len()
    );

    for (idx, json) in payloads.iter().enumerate() {
        // Log the top-level keys and type
        let top_keys: Vec<String> = json
            .as_object()
            .map(|o| o.keys().cloned().collect())
            .unwrap_or_default();
        let event_type = string_value(&json["type"]).unwrap_or_else(|| "(no type)".to_string());
        crate::provider_stderr_eprintln!(
            "[CLAUDE_DEBUG] line#{} payload#{}: type={}, keys={:?}",
            line_number,
            idx,
            event_type,
            top_keys
        );

        // Emit turn_started before the first meaningful event so the
        // Swift layer can create auto-todo placeholders and initialize
        // tool trace turns before any tool events arrive.
        if !*emitted_turn_started {
            *emitted_turn_started = true;
            crate::provider_stderr_eprintln!("[CLAUDE_DEBUG] >>> EMITTING turn_started");
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
                crate::provider_stderr_eprintln!(
                    "[CLAUDE_DEBUG] >>> EMITTING usage: {:?}",
                    payload
                );
                emit_raw(session_id, "usage", payload);
            }
        }
        if event_type == "result" {
            crate::provider_stderr_eprintln!(
                "[CLAUDE_DEBUG] GOT result event. received_stream_text={}",
                *received_stream_text
            );
            if let Some(result_text) = string_value(&json["result"]) {
                crate::provider_stderr_eprintln!(
                    "[CLAUDE_DEBUG] result text length={}",
                    result_text.len()
                );
            }
            // Skip result text when streaming already provided it —
            // the result event contains the full combined text
            // (reasoning + response) which would duplicate content.
            if !*received_stream_text {
                if let Some(result) = string_value(&json["result"]) {
                    crate::provider_stderr_eprintln!(
                        "[CLAUDE_DEBUG] >>> EMITTING text_delta from result (len={})",
                        result.len()
                    );
                    emit_text_delta(session_id, &result);
                }
            } else {
                crate::provider_stderr_eprintln!(
                    "[CLAUDE_DEBUG] SKIPPING result text (already streamed)"
                );
            }
            continue;
        }
        if event_type == "stream_event" {
            // Log the full event structure for debugging
            if let Some(event_obj) = json.get("event") {
                let event_type_inner = event_obj
                    .get("type")
                    .and_then(|v| v.as_str())
                    .unwrap_or("?");
                crate::provider_stderr_eprintln!(
                    "[CLAUDE_DEBUG] stream_event inner type={}",
                    event_type_inner
                );

                if let Some(delta) = event_obj.get("delta").and_then(|value| value.as_object()) {
                    let delta_type = delta
                        .get("type")
                        .and_then(string_value)
                        .unwrap_or_else(|| "(no delta type)".to_string());
                    crate::provider_stderr_eprintln!("[CLAUDE_DEBUG] delta type={}", delta_type);

                    if delta_type == "thinking_delta" {
                        if let Some(thinking) = delta.get("thinking").and_then(string_value) {
                            *received_stream_reasoning = true;
                            crate::provider_stderr_eprintln!(
                                "[CLAUDE_DEBUG] >>> EMITTING reasoning delta (len={})",
                                thinking.len()
                            );
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
                            crate::provider_stderr_eprintln!(
                                "[CLAUDE_DEBUG] thinking_delta but no 'thinking' field!"
                            );
                        }
                    }
                    if delta_type == "text_delta" {
                        if let Some(text) = delta.get("text").and_then(string_value) {
                            *received_stream_text = true;
                            crate::provider_stderr_eprintln!(
                                "[CLAUDE_DEBUG] >>> EMITTING text_delta (len={})",
                                text.len()
                            );
                            emit_text_delta(session_id, &text);
                        } else {
                            crate::provider_stderr_eprintln!(
                                "[CLAUDE_DEBUG] text_delta but no 'text' field!"
                            );
                        }
                    }
                    if delta_type != "thinking_delta" && delta_type != "text_delta" {
                        crate::provider_stderr_eprintln!(
                            "[CLAUDE_DEBUG] UNHANDLED delta type: {}",
                            delta_type
                        );
                        let delta_keys: Vec<String> = delta.keys().cloned().collect();
                        crate::provider_stderr_eprintln!(
                            "[CLAUDE_DEBUG]   delta keys: {:?}",
                            delta_keys
                        );
                    }
                } else {
                    crate::provider_stderr_eprintln!(
                        "[CLAUDE_DEBUG] stream_event has no delta object. event keys: {:?}",
                        event_obj
                            .as_object()
                            .map(|o| o.keys().cloned().collect::<Vec<_>>())
                    );
                }
            } else {
                crate::provider_stderr_eprintln!(
                    "[CLAUDE_DEBUG] stream_event but no 'event' field!"
                );
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
            crate::provider_stderr_eprintln!(
                "[CLAUDE_DEBUG] message.content has {} blocks (is_assistant={})",
                content.len(),
                is_assistant_message
            );
            if !is_assistant_message {
                crate::provider_stderr_eprintln!(
                    "[CLAUDE_DEBUG] SKIPPING non-assistant message content (type={})",
                    event_type
                );
            }
            for (bi, block) in content.iter().enumerate() {
                let block_type = block
                    .get("type")
                    .and_then(string_value)
                    .unwrap_or_else(|| "(no type)".to_string());
                crate::provider_stderr_eprintln!(
                    "[CLAUDE_DEBUG] message.content[{}] type={}",
                    bi,
                    block_type
                );

                // Emit tool_finish from tool_result blocks in user messages.
                // The result carries linesAdded/linesRemoved/output from the
                // MCP server — we must surface them so the UI cards show +/-.
                if block_type == "tool_result" && !is_assistant_message {
                    if let Some(tool_use_id) = block.get("tool_use_id").and_then(string_value) {
                        let mut result_payload = BTreeMap::new();
                        result_payload.insert("id".to_string(), tool_use_id);
                        result_payload.insert("type".to_string(), "tool_finish".to_string());
                        result_payload.insert("status".to_string(), "completed".to_string());
                        // Extract text content from the result
                        let result_text = block
                            .get("content")
                            .and_then(|c| {
                                if let Some(s) = c.as_str() {
                                    return Some(s.to_string());
                                }
                                if let Some(arr) = c.as_array() {
                                    for item in arr {
                                        if let Some(t) = item.get("text").and_then(|v| v.as_str()) {
                                            return Some(t.to_string());
                                        }
                                    }
                                }
                                None
                            })
                            .unwrap_or_default();
                        // Try to parse result_text as JSON to extract structured fields
                        if let Ok(result_json) =
                            serde_json::from_str::<serde_json::Value>(&result_text)
                        {
                            for (k, v) in flatten_string_map(&result_json) {
                                result_payload.entry(k).or_insert(v);
                            }
                        } else if !result_text.is_empty() {
                            result_payload.insert("output".to_string(), result_text);
                        }
                        crate::provider_stderr_eprintln!(
                            "[CLAUDE_DEBUG] >>> EMITTING tool_finish id={} keys={:?}",
                            result_payload.get("id").cloned().unwrap_or_default(),
                            result_payload.keys().cloned().collect::<Vec<_>>()
                        );
                        emit_raw(session_id, "tool_finish", result_payload);
                    }
                }

                if block_type == "text" && is_assistant_message {
                    // Skip final message text blocks if streaming already
                    // provided the text — avoids double-appending.
                    if !*received_stream_text {
                        if let Some(text) = block.get("text").and_then(string_value) {
                            crate::provider_stderr_eprintln!("[CLAUDE_DEBUG] >>> EMITTING text_delta from message.content (len={})", text.len());
                            emit_text_delta(session_id, &text);
                        }
                    } else {
                        crate::provider_stderr_eprintln!(
                            "[CLAUDE_DEBUG] SKIPPING message.content text (already streamed)"
                        );
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
                            crate::provider_stderr_eprintln!("[CLAUDE_DEBUG] >>> EMITTING reasoning from message.content (len={})", thinking.len());
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
                        crate::provider_stderr_eprintln!(
                            "[CLAUDE_DEBUG] SKIPPING message.content thinking (already streamed)"
                        );
                    }
                }
                if block_type == "tool_use" && is_assistant_message {
                    let name = block.get("name").and_then(string_value).unwrap_or_default();
                    crate::provider_stderr_eprintln!(
                        "[CLAUDE_DEBUG] >>> EMITTING tool_use name={}",
                        name
                    );
                    let mut payload = flatten_string_map(block);
                    // Merge nested `input` fields into the top-level payload
                    // so tool parameters (command, path, file_path, etc.)
                    // are visible to the Swift event mapper and UI cards.
                    if let Some(input) = block.get("input") {
                        let input_keys: Vec<String> = input
                            .as_object()
                            .map(|o| o.keys().cloned().collect())
                            .unwrap_or_default();
                        crate::provider_stderr_eprintln!(
                            "[CLAUDE_DEBUG]   tool input keys: {:?}",
                            input_keys
                        );
                        for (k, v) in flatten_string_map(input) {
                            payload.entry(k).or_insert(v);
                        }
                    }
                    // Mark tool as running so the UI shows a spinner until
                    // the tool_finish event arrives with status=completed.
                    payload
                        .entry("status".to_string())
                        .or_insert_with(|| "running".to_string());
                    let normalized = normalize_tool_name(&name);
                    crate::provider_stderr_eprintln!(
                        "[CLAUDE_DEBUG]   normalized tool name: {}",
                        normalized
                    );

                    // For subagent tools, inject swarm metadata so
                    // SwarmLiveReducer creates visible subagent cards.
                    // Each sub-agent gets a unique swarm_id based on the tool_use_id.
                    if is_subagent_tool(&name) {
                        let role_name = subagent_role_name(&name);
                        let agent_label = subagent_display_name(&name);
                        let tool_use_id = payload
                            .get("id")
                            .cloned()
                            .unwrap_or_else(|| format!("sa-{}", session_id));
                        let sid = make_swarm_id(&tool_use_id);
                        let task_text = payload.get("task").cloned().unwrap_or_default();
                        let readable = subagent_readable_name(&task_text, &agent_label);
                        payload.entry("swarm_id".to_string()).or_insert(sid.clone());
                        payload
                            .entry("group_id".to_string())
                            .or_insert(format!("swarm-{}", sid));
                        payload
                            .entry("agent_name".to_string())
                            .or_insert(agent_label);
                        payload
                            .entry("readable_name".to_string())
                            .or_insert(readable.clone());
                        payload.entry("role".to_string()).or_insert(role_name);
                        payload.entry("title".to_string()).or_insert(readable);
                        payload
                            .entry("detail".to_string())
                            .or_insert("started".to_string());
                        if !task_text.is_empty() {
                            let preview = truncate_str(&task_text, 500);
                            payload.entry("task_summary".to_string()).or_insert(preview);
                        }
                    }

                    emit_raw(session_id, &normalized, payload);
                }
                if block_type != "text" && block_type != "thinking" && block_type != "tool_use" {
                    crate::provider_stderr_eprintln!(
                        "[CLAUDE_DEBUG] UNHANDLED message.content block type: {}",
                        block_type
                    );
                }
            }
        }
        // Handle system subtype events for subagent lifecycle.
        if event_type == "system" {
            let subtype = json
                .get("subtype")
                .and_then(string_value)
                .unwrap_or_default();

            // task_started: a new subagent was launched
            if subtype == "task_started" {
                // Log ALL fields
                if let Some(obj) = json.as_object() {
                    let keys: Vec<String> = obj.keys().cloned().collect();
                    crate::provider_stderr_eprintln!(
                        "[CLAUDE_DEBUG] task_started ALL keys: {:?}",
                        keys
                    );
                }
                let tool_use_id = json
                    .get("tool_use_id")
                    .and_then(string_value)
                    .unwrap_or_default();
                let task_id = json
                    .get("task_id")
                    .and_then(string_value)
                    .unwrap_or_default();
                let description = json
                    .get("description")
                    .and_then(string_value)
                    .unwrap_or_default();
                let prompt = json
                    .get("prompt")
                    .and_then(string_value)
                    .unwrap_or_default();
                crate::provider_stderr_eprintln!(
                    "[CLAUDE_DEBUG] task_started: id={} desc={}",
                    task_id,
                    description
                );
                if !tool_use_id.is_empty() {
                    let sid = make_swarm_id(&tool_use_id);
                    let readable = subagent_readable_name(&prompt, &description);
                    let mut payload = BTreeMap::new();
                    payload.insert("id".to_string(), tool_use_id);
                    payload.insert("task_id".to_string(), task_id);
                    payload.insert("status".to_string(), "running".to_string());
                    payload.insert("readable_name".to_string(), readable.clone());
                    payload.insert("title".to_string(), readable);
                    payload.insert("detail".to_string(), "started".to_string());
                    payload.insert("task_summary".to_string(), truncate_str(&prompt, 500));
                    payload.insert("swarm_id".to_string(), sid.clone());
                    payload.insert("group_id".to_string(), format!("swarm-{}", sid));
                    emit_raw(session_id, "agent", payload);
                }
            }

            // task_progress: subagent is doing work
            if subtype == "task_progress" {
                // Log ALL fields in task_progress so we can see what Claude sends
                if let Some(obj) = json.as_object() {
                    let keys: Vec<String> = obj.keys().cloned().collect();
                    crate::provider_stderr_eprintln!(
                        "[CLAUDE_DEBUG] task_progress ALL keys: {:?}",
                        keys
                    );
                    for (k, v) in obj {
                        if let Some(s) = string_value(v) {
                            let preview = clip_utf8_prefix(&s, 200);
                            crate::provider_stderr_eprintln!(
                                "[CLAUDE_DEBUG]   task_progress.{} = {}",
                                k,
                                preview
                            );
                        }
                    }
                }
                let tool_use_id = json
                    .get("tool_use_id")
                    .and_then(string_value)
                    .unwrap_or_default();
                let description = json
                    .get("description")
                    .and_then(string_value)
                    .unwrap_or_default();
                let last_tool = json
                    .get("last_tool_name")
                    .and_then(string_value)
                    .unwrap_or_default();
                // Check for content/output/text fields that might carry actual sub-agent output
                let content = json
                    .get("content")
                    .and_then(string_value)
                    .unwrap_or_default();
                let output = json
                    .get("output")
                    .and_then(string_value)
                    .unwrap_or_default();
                let tool_input = json
                    .get("tool_input")
                    .and_then(|v| serde_json::to_string(v).ok())
                    .unwrap_or_default();
                let tool_result = json
                    .get("tool_result")
                    .and_then(string_value)
                    .unwrap_or_default();

                if !tool_use_id.is_empty() {
                    let sid = make_swarm_id(&tool_use_id);
                    let step_title = if !last_tool.is_empty() {
                        format!("{} — {}", last_tool, description)
                    } else {
                        description.clone()
                    };
                    let mut payload = BTreeMap::new();
                    payload.insert("id".to_string(), tool_use_id);
                    payload.insert("status".to_string(), "running".to_string());
                    payload.insert("detail".to_string(), description.clone());
                    payload.insert("title".to_string(), step_title.clone());
                    payload.insert("text".to_string(), step_title);
                    payload.insert("swarm_id".to_string(), sid.clone());
                    payload.insert("group_id".to_string(), format!("swarm-{}", sid));
                    // Forward any tool name/input/result for richer activity display
                    if !last_tool.is_empty() {
                        payload.insert("tool".to_string(), last_tool);
                    }
                    if !content.is_empty() {
                        payload.insert("content".to_string(), truncate_str(&content, 2000));
                    }
                    if !output.is_empty() {
                        payload.insert("output".to_string(), truncate_str(&output, 2000));
                    }
                    if !tool_input.is_empty() && tool_input != "{}" && tool_input != "null" {
                        payload.insert("tool_input".to_string(), truncate_str(&tool_input, 1000));
                    }
                    if !tool_result.is_empty() {
                        payload.insert("tool_result".to_string(), truncate_str(&tool_result, 2000));
                    }
                    // Emit as activity event (for tool trace in chat)
                    emit_raw(session_id, "subagent_text", payload.clone());

                    // Also emit as agent event so it shows as a real tool operation
                    let last_tool_ref = payload.get("tool").cloned().unwrap_or_default();
                    if !last_tool_ref.is_empty() {
                        let mut tool_payload = BTreeMap::new();
                        tool_payload.insert(
                            "id".to_string(),
                            payload.get("id").cloned().unwrap_or_default(),
                        );
                        tool_payload.insert("title".to_string(), last_tool_ref.clone());
                        tool_payload.insert("detail".to_string(), description.clone());
                        tool_payload.insert("status".to_string(), "completed".to_string());
                        tool_payload.insert("tool".to_string(), last_tool_ref);
                        tool_payload.insert("swarm_id".to_string(), sid.clone());
                        tool_payload.insert("group_id".to_string(), format!("swarm-{}", sid));
                        if !content.is_empty() {
                            tool_payload.insert("output".to_string(), truncate_str(&content, 2000));
                        }
                        if !output.is_empty() {
                            tool_payload.insert("output".to_string(), truncate_str(&output, 2000));
                        }
                        emit_raw(session_id, "mcp_tool_call", tool_payload);
                    }
                }
            }

            // task_notification: subagent completed or failed
            if subtype == "task_notification" {
                // Log ALL fields
                if let Some(obj) = json.as_object() {
                    let keys: Vec<String> = obj.keys().cloned().collect();
                    crate::provider_stderr_eprintln!(
                        "[CLAUDE_DEBUG] task_notification ALL keys: {:?}",
                        keys
                    );
                    for (k, v) in obj {
                        if let Some(s) = string_value(v) {
                            let preview = clip_utf8_prefix(&s, 300);
                            crate::provider_stderr_eprintln!(
                                "[CLAUDE_DEBUG]   task_notification.{} = {}",
                                k,
                                preview
                            );
                        }
                    }
                }
                let status = json
                    .get("status")
                    .and_then(string_value)
                    .unwrap_or_default();
                let tool_use_id = json
                    .get("tool_use_id")
                    .and_then(string_value)
                    .unwrap_or_default();
                let summary = json
                    .get("summary")
                    .and_then(string_value)
                    .unwrap_or_default();
                crate::provider_stderr_eprintln!(
                    "[CLAUDE_DEBUG] task_notification: status={} id={} summary={}",
                    status,
                    tool_use_id,
                    summary
                );
                if status == "completed" || status == "failed" {
                    let sid = make_swarm_id(&tool_use_id);
                    // Emit the summary as assistant text so it appears in the chat
                    if !summary.is_empty() {
                        let mut text_payload = BTreeMap::new();
                        text_payload.insert("id".to_string(), tool_use_id.clone());
                        text_payload.insert("status".to_string(), "running".to_string());
                        text_payload.insert("detail".to_string(), summary.clone());
                        text_payload.insert("title".to_string(), "Response".to_string());
                        text_payload.insert("text".to_string(), summary.clone());
                        text_payload.insert("source".to_string(), "assistant".to_string());
                        text_payload.insert("swarm_id".to_string(), sid.clone());
                        text_payload.insert("group_id".to_string(), format!("swarm-{}", sid));
                        emit_raw(session_id, "subagent_text", text_payload);
                    }
                    // Emit the completion event
                    let mut payload = BTreeMap::new();
                    payload.insert("id".to_string(), tool_use_id);
                    payload.insert("status".to_string(), status.clone());
                    payload.insert("detail".to_string(), status);
                    payload.insert("title".to_string(), "Completed".to_string());
                    payload.insert("output".to_string(), summary);
                    payload.insert("swarm_id".to_string(), sid.clone());
                    payload.insert("group_id".to_string(), format!("swarm-{}", sid));
                    emit_raw(session_id, "agent", payload);
                }
            }

            // Log unhandled system subtypes
            if subtype != "task_started"
                && subtype != "task_progress"
                && subtype != "task_notification"
                && !subtype.is_empty()
            {
                crate::provider_stderr_eprintln!(
                    "[CLAUDE_DEBUG] UNHANDLED system subtype: {} keys: {:?}",
                    subtype,
                    json.as_object()
                        .map(|o| o.keys().cloned().collect::<Vec<_>>())
                );
            }
        }
        // Check for unhandled event types
        if event_type != "result"
            && event_type != "stream_event"
            && event_type != "(no type)"
            && event_type != "system"
        {
            crate::provider_stderr_eprintln!(
                "[CLAUDE_DEBUG] UNHANDLED top-level event type: {}",
                event_type
            );
        }
        // Check for errors
        if let Some(error) = json
            .get("error")
            .and_then(|v| v.as_str())
            .or_else(|| json.get("message").and_then(|v| v.as_str()))
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
        {
            crate::provider_stderr_eprintln!("[CLAUDE_DEBUG] ERROR: {}", error);
            if error.to_lowercase().contains("rate limit") || error.to_lowercase().contains("quota")
            {
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

/// Returns true if the tool name is a coderide subagent tool.
fn is_subagent_tool(name: &str) -> bool {
    let lower = name.to_lowercase();
    lower.contains("subagent_") || lower == "agent"
}

/// Generates a stable, unique swarm_id from a tool_use_id.
/// MUST produce the SAME id for the SAME tool_use_id across tool_use,
/// task_started, task_progress, and task_notification events.
/// The swarm_id is internal — never shown to the user.
fn make_swarm_id(tool_use_id: &str) -> String {
    // Use last 12 chars (unique part; Claude IDs always start with "toolu_01")
    let len = tool_use_id.len();
    let suffix = if len > 12 {
        &tool_use_id[len - 12..]
    } else {
        tool_use_id
    };
    format!("sa-{}", suffix)
}

/// Truncates a string to a max number of characters, appending "…" if truncated.
/// Truncate to at most `max_bytes` UTF-8 bytes without splitting a scalar value (avoids panics).
fn clip_utf8_prefix(s: &str, max_bytes: usize) -> &str {
    if s.len() <= max_bytes {
        return s;
    }
    let mut end = max_bytes;
    while end > 0 && !s.is_char_boundary(end) {
        end -= 1;
    }
    &s[..end]
}

fn truncate_str(s: &str, max_chars: usize) -> String {
    if s.len() <= max_chars {
        return s.to_string();
    }
    let end = s.char_indices().nth(max_chars).map_or(s.len(), |(i, _)| i);
    format!("{}…", &s[..end])
}

/// Extracts the raw role name from a subagent tool name (e.g. "explorer", "coder").
fn subagent_role_name(name: &str) -> String {
    let lower = name.to_lowercase();
    if let Some(suffix) = lower
        .strip_prefix("mcp__coderide__coderide_subagent_")
        .or_else(|| lower.strip_prefix("subagent_"))
    {
        suffix.to_string()
    } else {
        "agent".to_string()
    }
}

/// Derives a readable display name from a task string by extracting key words.
fn subagent_readable_name(task: &str, fallback: &str) -> String {
    if task.is_empty() {
        return fallback.to_string();
    }
    let filler_words: std::collections::HashSet<&str> = [
        "a",
        "an",
        "and",
        "are",
        "as",
        "at",
        "be",
        "by",
        "for",
        "from",
        "i",
        "in",
        "into",
        "of",
        "on",
        "or",
        "the",
        "this",
        "to",
        "with",
        "analyze",
        "check",
        "explore",
        "find",
        "inspect",
        "investigate",
        "review",
        "search",
        "verify",
        "create",
        "implement",
        "write",
        "build",
        "code",
        "debug",
        "fix",
        "test",
        "document",
    ]
    .iter()
    .copied()
    .collect();

    let words: Vec<String> = task
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || c == ' ' {
                c
            } else {
                ' '
            }
        })
        .collect::<String>()
        .split_whitespace()
        .filter(|w| !filler_words.contains(&w.to_lowercase().as_str()) && w.len() > 1)
        .take(5)
        .map(|w| {
            let mut chars = w.chars();
            match chars.next() {
                None => String::new(),
                Some(c) => c.to_uppercase().to_string() + &chars.as_str().to_lowercase(),
            }
        })
        .collect();

    if words.is_empty() {
        return fallback.to_string();
    }
    let result = words.join(" ");
    if result.len() > 60 {
        clip_utf8_prefix(&result, 60).to_string()
    } else {
        result
    }
}

/// Extracts a human-friendly display name from a subagent tool name.
fn subagent_display_name(name: &str) -> String {
    let lower = name.to_lowercase();
    if let Some(suffix) = lower
        .strip_prefix("mcp__coderide__coderide_subagent_")
        .or_else(|| lower.strip_prefix("subagent_"))
    {
        // e.g. "explorer" → "Explorer", "bugHunter" → "Bug Hunter"
        let mut result = String::new();
        for (i, ch) in suffix.chars().enumerate() {
            if i == 0 {
                result.extend(ch.to_uppercase());
            } else if ch.is_uppercase() {
                result.push(' ');
                result.push(ch);
            } else {
                result.push(ch);
            }
        }
        result
    } else {
        "Agent".to_string()
    }
}

fn normalize_tool_name(name: &str) -> String {
    let lowered = name.trim().to_lowercase();
    // Strip MCP coderide prefix so the Swift UI mapper recognizes the
    // tool name (e.g. "mcp__coderide__coderide_read" → "read").
    let stripped = lowered
        .strip_prefix("mcp__coderide__coderide_")
        .unwrap_or(&lowered);
    match stripped {
        "mermaidrender" => "mermaid_render".to_string(),
        "planrequestuserinput" => "plan_request_user_input".to_string(),
        // Map coderide MCP tool names to the simple names the Swift
        // ProviderToolEventMapper recognizes for card rendering.
        "exec" => "bash".to_string(),
        "file_outline" => "read".to_string(),
        "list_dir" => "list_dir".to_string(),
        "subagent_explorer" | "subagent_bughunter" | "subagent_securityauditor" => {
            "agent".to_string()
        }
        "policy_ack" => "policy_ack".to_string(),
        "todo_write" | "todo_read" | "todo_update" => "todo_write".to_string(),
        "plan_create" | "plan_update" | "plan_read" => "plan_create".to_string(),
        other => other.replace('-', "_"),
    }
}

/// Returns the coderide-specific system prompt that instructs Claude to
/// follow the IDE workflow: create todos first, use enhanced tools, etc.
fn coderide_system_prompt() -> &'static str {
    r#"
# Coderide IDE Integration — MANDATORY Workflow

You are running inside the Coderide IDE. You MUST follow these rules:

## 1. TODO LIST — ABSOLUTE RULE: ONE AT A TIME, TOP TO BOTTOM

BEFORE any work, call `mcp__coderide__coderide_todo_write` to create your todo list.

**CRITICAL CONSTRAINT — you MUST obey ALL of these:**
- Only ONE todo can be "in_progress" at any time. All others must be "pending".
- ALWAYS start from todo #1 (the top). NEVER jump to #5 or any later item first.
- Complete #1 fully, then call `coderide_todo_write` to mark #1 as "completed" and #2 as "in_progress".
- Then complete #2, mark it "completed", move #3 to "in_progress". And so on.
- NEVER work on multiple todos simultaneously. NEVER mark multiple items "completed" in one update.
- NEVER reorder todos after creation. Completed items stay in their original position.
- If you discover new work, append it at the END of the list, never insert before pending items.

**VIOLATION CHECK:** If you are about to start work on todo N while todo N-1 is still pending, STOP. Go back and do N-1 first.

## 2. Prefer enhanced coderide tools
- **Search**: `coderide_semantic_search`, `coderide_codebase_search`, `coderide_grep`
- **Read**: `coderide_read`, `coderide_read_range`
- **Edit**: `coderide_str_replace`, `coderide_regex_replace`, `coderide_write`
- **Explore**: `coderide_file_outline`, `coderide_find_symbol`, `coderide_find_references`, `coderide_list_dir`
- **Diagnostics**: `coderide_diagnostics`, `coderide_read_lints`

**ABSOLUTE TOOL PRECEDENCE**
- Use the `coderide_*` tool first when a coderide tool exists for the job.
- Do NOT use Claude native search/read/edit tools as first choice when an equivalent `coderide_*` tool is available.
- Do NOT use shell workspace discovery with `grep`, `rg`, `find`, `fd`, `cat`, `ls`, or `tree`.
- Use shell only for git, builds, tests, and dependency/install commands.
- For natural-language code discovery, use `coderide_semantic_search`.
- For exact text or regex search, use `coderide_grep`.

## 3. Subagents
- For real delegation, use Claude's native Task/subagent capability.
- Give each Task a clear role in the prompt (explorer, coder, reviewer, test writer, security auditor, bug hunter) and let Claude manage the child context natively.
- Do NOT use `coderide_subagent_*` MCP tools as a proxy for real subagent execution in main chat; those are launch shims and do not represent the child lifecycle.

## 4. Plans
For complex tasks, create a plan with `coderide_plan_create` after the todo.

## 5. Language
Follow the user's language preference from their CLAUDE.md instructions.
"#
}

/// Writes a temporary MCP config JSON so Claude CLI can connect to our
/// coderide MCP server and use its custom tools (todo, plan, debug, etc.).
/// Returns the file path if successful, `None` otherwise.
fn write_mcp_config(config: &MainChatProviderSessionConfig) -> Option<String> {
    let server_path = config.claude_mcp_server_path.as_deref()?.trim();
    if server_path.is_empty() {
        crate::provider_stderr_eprintln!("[CLAUDE_DEBUG] write_mcp_config: server_path is empty");
        return None;
    }
    if !std::path::Path::new(server_path).exists() {
        crate::provider_stderr_eprintln!(
            "[CLAUDE_DEBUG] write_mcp_config: server_path does not exist: {}",
            server_path
        );
        return None;
    }
    crate::provider_stderr_eprintln!(
        "[CLAUDE_DEBUG] write_mcp_config: using server at {}",
        server_path
    );
    let escaped_path = server_path.replace('\\', "\\\\").replace('"', "\\\"");
    let escaped_workspace = config
        .workspace_path
        .replace('\\', "\\\\")
        .replace('"', "\\\"");
    let config_json = format!(
        "{{\n  \"mcpServers\": {{\n    \"coderide\": {{\n      \"command\": \"{}\",\n      \"args\": [],\n      \"env\": {{\n        \"SOLOCODE_WORKSPACE\": \"{}\"\n      }}\n    }}\n  }}\n}}",
        escaped_path,
        escaped_workspace,
    );
    let tmp_dir = std::env::temp_dir().join("solocode-claude-mcp");
    std::fs::create_dir_all(&tmp_dir).ok()?;
    let config_path = tmp_dir.join("mcp-config.json");
    std::fs::write(&config_path, &config_json).ok()?;
    crate::provider_stderr_eprintln!(
        "[CLAUDE_DEBUG] write_mcp_config: wrote config to {}",
        config_path.display()
    );
    crate::provider_stderr_eprintln!("[CLAUDE_DEBUG] write_mcp_config: content={}", config_json);
    Some(config_path.to_string_lossy().into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    // -- make_swarm_id --

    #[test]
    fn make_swarm_id_uses_last_12_chars() {
        let id = "toolu_01AbCdEfGhIjKlMn";
        let sid = make_swarm_id(id);
        // 22 chars total, last 12 = "CdEfGhIjKlMn"
        assert_eq!(sid, "sa-CdEfGhIjKlMn");
        assert!(!sid.contains("toolu_01"));
    }

    #[test]
    fn make_swarm_id_short_id_kept_intact() {
        let sid = make_swarm_id("abc123");
        assert_eq!(sid, "sa-abc123");
    }

    #[test]
    fn make_swarm_id_same_id_always_same_result() {
        let id = "toolu_01XyZaBcDeFgHiJk";
        assert_eq!(make_swarm_id(id), make_swarm_id(id));
    }

    #[test]
    fn make_swarm_id_different_ids_produce_different_results() {
        let a = make_swarm_id("toolu_01AAAAAAAAAAAA");
        let b = make_swarm_id("toolu_01BBBBBBBBBBBB");
        assert_ne!(a, b);
    }

    // -- is_subagent_tool --

    #[test]
    fn is_subagent_tool_detects_subagent_prefix() {
        assert!(is_subagent_tool("subagent_explorer"));
        assert!(is_subagent_tool("mcp__coderide__coderide_subagent_coder"));
        assert!(is_subagent_tool("SUBAGENT_DEBUGGER"));
    }

    #[test]
    fn is_subagent_tool_rejects_normal_tools() {
        assert!(!is_subagent_tool("read"));
        assert!(!is_subagent_tool("bash"));
        assert!(!is_subagent_tool("grep"));
    }

    // -- subagent_role_name --

    #[test]
    fn subagent_role_name_extracts_role() {
        assert_eq!(subagent_role_name("subagent_explorer"), "explorer");
        assert_eq!(
            subagent_role_name("mcp__coderide__coderide_subagent_coder"),
            "coder"
        );
    }

    #[test]
    fn subagent_role_name_fallback_for_unknown() {
        assert_eq!(subagent_role_name("read"), "agent");
    }

    // -- subagent_display_name --

    #[test]
    fn subagent_display_name_capitalizes() {
        assert_eq!(subagent_display_name("subagent_explorer"), "Explorer");
        assert_eq!(
            subagent_display_name("mcp__coderide__coderide_subagent_coder"),
            "Coder"
        );
    }

    #[test]
    fn subagent_display_name_fallback() {
        assert_eq!(subagent_display_name("read"), "Agent");
    }

    // -- subagent_readable_name --

    #[test]
    fn readable_name_extracts_key_words() {
        let name = subagent_readable_name(
            "Investigate the auth token refresh flow and session invalidation",
            "Explorer",
        );
        assert!(!name.is_empty());
        assert!(name.contains(' '), "Should have spaces: {}", name);
        // Should not contain filler words
        assert!(!name.to_lowercase().contains("the "));
        assert!(!name.to_lowercase().contains("and "));
    }

    #[test]
    fn readable_name_caps_at_5_words() {
        let name = subagent_readable_name(
            "first second third fourth fifth sixth seventh eighth",
            "Fallback",
        );
        let word_count = name.split_whitespace().count();
        assert!(word_count <= 5, "Got {} words: {}", word_count, name);
    }

    #[test]
    fn readable_name_falls_back_when_empty_task() {
        let name = subagent_readable_name("", "Explorer");
        assert_eq!(name, "Explorer");
    }

    #[test]
    fn coderide_system_prompt_prefers_native_task_tool_for_subagents() {
        let prompt = coderide_system_prompt();
        assert!(prompt.contains("native Task/subagent capability"));
        assert!(prompt.contains("Do NOT use `coderide_subagent_*` MCP tools"));
    }

    #[test]
    fn readable_name_max_60_chars() {
        let long = "Aaaaaaaaaaaaa ".repeat(20);
        let name = subagent_readable_name(&long, "Fallback");
        assert!(name.len() <= 60, "Too long: {} chars", name.len());
    }

    // -- truncate_str --

    #[test]
    fn truncate_str_short_unchanged() {
        assert_eq!(truncate_str("hello", 10), "hello");
    }

    #[test]
    fn truncate_str_long_truncated() {
        let long = "a".repeat(600);
        let result = truncate_str(&long, 500);
        assert!(result.len() <= 504); // 500 + "…"
        assert!(result.ends_with('…'));
    }

    #[test]
    fn clip_utf8_prefix_never_splits_codepoint() {
        let s = "€".repeat(100);
        let clipped = clip_utf8_prefix(&s, 200);
        assert!(clipped.len() <= 200);
        assert!(s.starts_with(clipped));
    }
}
