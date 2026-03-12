use serde_json::{json, Value};
use std::fs;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn initialize_and_list_tools_work() {
    let home = make_temp_dir("rust-mcp-home");
    let workspace = make_temp_dir("rust-mcp-workspace");
    let mut child = spawn_server(&home, &workspace);

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-11-25",
                "capabilities": {},
                "clientInfo": { "name": "test", "version": "1.0.0" }
            }
        }),
    );
    let init = read_message(&mut child);
    assert_eq!(init["result"]["serverInfo"]["name"], "coderide-tools-rust");

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        }),
    );
    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list"
        }),
    );
    let listed = read_message(&mut child);
    let tools = listed["result"]["tools"].as_array().expect("tools array");
    assert!(tools.iter().any(|tool| tool["name"] == "coderide_read"));
    assert!(tools.iter().any(|tool| tool["name"] == "coderide_todo_read"));
    terminate(child);
}

#[test]
fn todo_read_and_subagent_ack_work() {
    let home = make_temp_dir("rust-mcp-home");
    let workspace = make_temp_dir("rust-mcp-workspace");
    let todos_path = home
        .join("Library")
        .join("Application Support")
        .join("CoderIDE")
        .join("mcp-shared");
    fs::create_dir_all(&todos_path).expect("create todos dir");
    fs::write(
        todos_path.join("todos.json"),
        serde_json::to_vec_pretty(&vec![json!({
            "title": "Migrare MCP runtime",
            "status": "in_progress",
            "priority": "high",
            "activeForm": "Sto migrando il server",
            "linkedFiles": ["Native/CoderideMCPServerRust/src/server.rs"]
        })])
        .expect("serialize todos"),
    )
    .expect("write todos");

    let mut child = spawn_server(&home, &workspace);
    initialize(&mut child);

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "coderide_todo_read",
                "arguments": {}
            }
        }),
    );
    let todo_result = read_message(&mut child);
    let todo_text = todo_result["result"]["content"][0]["text"]
        .as_str()
        .expect("todo text");
    assert!(todo_text.contains("Migrare MCP runtime"));

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {
                "name": "coderide_subagent_explorer",
                "arguments": { "task": "Ispeziona il runtime MCP" }
            }
        }),
    );
    let ack = read_message(&mut child);
    assert_eq!(
        ack["result"]["content"][0]["text"].as_str(),
        Some("OK — subagent Explorer launched")
    );
    terminate(child);
}

#[test]
fn plan_tools_and_ide_acks_work() {
    let home = make_temp_dir("rust-mcp-home");
    let workspace = make_temp_dir("rust-mcp-workspace");
    let mut child = spawn_server(&home, &workspace);
    initialize(&mut child);

    let conversation_id = "11111111-1111-1111-1111-111111111111";
    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 10,
            "method": "tools/call",
            "params": {
                "name": "coderide_plan_create",
                "arguments": {
                    "conversation_id": conversation_id,
                    "goal": "Migrare MCP runtime",
                    "steps": [
                        { "id": "1", "title": "Analisi", "status": "pending" }
                    ]
                }
            }
        }),
    );
    let create = read_message(&mut child);
    assert_eq!(
        create["result"]["content"][0]["text"].as_str(),
        Some("OK — plan snapshot created")
    );

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 11,
            "method": "tools/call",
            "params": {
                "name": "coderide_plan_step_upsert",
                "arguments": {
                    "conversation_id": conversation_id,
                    "step_id": "2",
                    "status": "running",
                    "title": "Implementazione"
                }
            }
        }),
    );
    let upsert = read_message(&mut child);
    assert_eq!(
        upsert["result"]["content"][0]["text"].as_str(),
        Some("OK — plan step 2 upserted")
    );

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 12,
            "method": "tools/call",
            "params": {
                "name": "coderide_plan_read",
                "arguments": {
                    "conversation_id": conversation_id,
                    "include_history": true,
                    "history_limit": 5
                }
            }
        }),
    );
    let read = read_message(&mut child);
    let read_text = read["result"]["content"][0]["text"].as_str().expect("plan read text");
    let read_json: Value = serde_json::from_str(read_text).expect("plan read json");
    assert_eq!(read_json["conversation_id"], conversation_id);
    assert_eq!(read_json["snapshot"]["goal"], "Migrare MCP runtime");

    let snapshot_id = read_json["snapshot"]["snapshotId"].as_str().expect("snapshot id");
    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 13,
            "method": "tools/call",
            "params": {
                "name": "coderide_plan_diff",
                "arguments": {
                    "from_snapshot_id": snapshot_id
                }
            }
        }),
    );
    let diff = read_message(&mut child);
    let diff_text = diff["result"]["content"][0]["text"].as_str().expect("plan diff text");
    let diff_json: Value = serde_json::from_str(diff_text).expect("plan diff json");
    assert_eq!(diff_json["from_snapshot_id"], snapshot_id);

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 14,
            "method": "tools/call",
            "params": {
                "name": "coderide_policy_ack",
                "arguments": { "hash": "abc123" }
            }
        }),
    );
    let policy = read_message(&mut child);
    assert_eq!(
        policy["result"]["content"][0]["text"].as_str(),
        Some("OK — policy acknowledged")
    );

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 15,
            "method": "tools/call",
            "params": {
                "name": "coderide_mermaid_render",
                "arguments": {
                    "code": "graph TD; A-->B;",
                    "title": "Flow"
                }
            }
        }),
    );
    let mermaid = read_message(&mut child);
    assert_eq!(
        mermaid["result"]["content"][0]["text"].as_str(),
        Some("OK — mermaid diagram rendered in IDE (Flow)")
    );

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 16,
            "method": "tools/call",
            "params": {
                "name": "coderide_plan_step_batch_update",
                "arguments": {
                    "conversation_id": conversation_id,
                    "updates": [
                        { "stepId": "1", "status": "running", "targetFile": "Sources/New.swift" }
                    ]
                }
            }
        }),
    );
    let batch = read_message(&mut child);
    assert_eq!(
        batch["result"]["content"][0]["text"].as_str(),
        Some("OK — batch plan update applied (1 steps)")
    );

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 17,
            "method": "tools/call",
            "params": {
                "name": "coderide_plan_step_dependency_set",
                "arguments": {
                    "conversation_id": conversation_id,
                    "step_id": "1",
                    "depends_on": ["0"]
                }
            }
        }),
    );
    let deps = read_message(&mut child);
    assert_eq!(
        deps["result"]["content"][0]["text"].as_str(),
        Some("OK — dependencies set for step 1")
    );

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 18,
            "method": "tools/call",
            "params": {
                "name": "coderide_plan_step_reorder",
                "arguments": {
                    "conversation_id": conversation_id,
                    "ordered_step_ids": ["2", "1"]
                }
            }
        }),
    );
    let reorder = read_message(&mut child);
    assert_eq!(
        reorder["result"]["content"][0]["text"].as_str(),
        Some("OK — plan step order updated")
    );

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 19,
            "method": "tools/call",
            "params": {
                "name": "coderide_plan_set_walkthrough",
                "arguments": {
                    "conversation_id": conversation_id,
                    "markdown": "## Done",
                    "summary": "Stored",
                    "outcome": "done"
                }
            }
        }),
    );
    let walkthrough = read_message(&mut child);
    assert_eq!(
        walkthrough["result"]["content"][0]["text"].as_str(),
        Some("OK — walkthrough stored")
    );

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 20,
            "method": "tools/call",
            "params": {
                "name": "coderide_plan_request_user_input",
                "arguments": {
                    "title": "Clarify deployment",
                    "phase": "post-analysis",
                    "round": "2",
                    "questions": [
                        {
                            "prompt": "Target environment?",
                            "options": [
                                { "label": "Production" },
                                { "label": "Staging" }
                            ]
                        }
                    ]
                }
            }
        }),
    );
    let questionnaire = read_message(&mut child);
    assert_eq!(
        questionnaire["result"]["content"][0]["text"].as_str(),
        Some("OK — queued 1 clarification question(s) [title: Clarify deployment | phase: post-analysis | round: 2]")
    );
    terminate(child);
}

#[test]
fn search_tools_work() {
    let home = make_temp_dir("rust-mcp-home");
    let workspace = make_temp_dir("rust-mcp-workspace");
    let source = workspace.join("Sample.swift");
    fs::write(
        &source,
        "import Foundation\nstruct Sample {}\nfunc greet() {\n    let token = Sample()\n    print(token)\n}\n",
    )
    .expect("write source");

    let mut child = spawn_server(&home, &workspace);
    initialize(&mut child);

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":30,"method":"tools/call",
        "params":{"name":"coderide_read_range","arguments":{"path":"Sample.swift","start_line":2,"end_line":4}}
    }));
    let read_range = read_message(&mut child);
    assert!(read_range["result"]["content"][0]["text"].as_str().unwrap_or("").contains("2: struct Sample {}"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":31,"method":"tools/call",
        "params":{"name":"coderide_find_files","arguments":{"query":"Sample.swift"}}
    }));
    let find_files = read_message(&mut child);
    assert!(find_files["result"]["content"][0]["text"].as_str().unwrap_or("").contains("Sample.swift"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":32,"method":"tools/call",
        "params":{"name":"coderide_find_symbol","arguments":{"query":"Sample"}}
    }));
    let find_symbol = read_message(&mut child);
    assert!(find_symbol["result"]["content"][0]["text"].as_str().unwrap_or("").contains("Sample.swift:2"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":33,"method":"tools/call",
        "params":{"name":"coderide_find_references","arguments":{"query":"Sample"}}
    }));
    let references = read_message(&mut child);
    assert!(references["result"]["content"][0]["text"].as_str().unwrap_or("").contains("Sample.swift:4"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":34,"method":"tools/call",
        "params":{"name":"coderide_file_outline","arguments":{"path":"Sample.swift"}}
    }));
    let outline = read_message(&mut child);
    assert!(outline["result"]["content"][0]["text"].as_str().unwrap_or("").contains("2: struct Sample {}"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":35,"method":"tools/call",
        "params":{"name":"coderide_codebase_search","arguments":{"query":"token"}}
    }));
    let codebase = read_message(&mut child);
    assert!(codebase["result"]["content"][0]["text"].as_str().unwrap_or("").contains("Sample.swift:4"));
    terminate(child);
}

fn initialize(child: &mut std::process::Child) {
    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-11-25",
                "capabilities": {},
                "clientInfo": { "name": "test", "version": "1.0.0" }
            }
        }),
    );
    let _ = read_message(child);
    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        }),
    );
}

fn spawn_server(home: &PathBuf, workspace: &PathBuf) -> std::process::Child {
    Command::new(env!("CARGO_BIN_EXE_coderide-mcp-server-rust"))
        .arg("--workspace")
        .arg(workspace)
        .env("HOME", home)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("spawn server")
}

fn write_message(stdin: &mut std::process::ChildStdin, payload: Value) {
    let encoded = serde_json::to_string(&payload).expect("encode request");
    stdin.write_all(encoded.as_bytes()).expect("write request");
    stdin.write_all(b"\n").expect("write newline");
    stdin.flush().expect("flush stdin");
}

fn read_message(child: &mut std::process::Child) -> Value {
    let stdout = child.stdout.as_mut().expect("stdout");
    let mut bytes = Vec::new();
    loop {
        let mut byte = [0u8; 1];
        stdout.read_exact(&mut byte).expect("read response byte");
        if byte[0] == b'\n' {
            break;
        }
        bytes.push(byte[0]);
    }
    serde_json::from_slice(&bytes).expect("decode response")
}

fn terminate(mut child: std::process::Child) {
    let _ = child.kill();
    let _ = child.wait();
}

fn make_temp_dir(prefix: &str) -> PathBuf {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("time")
        .as_nanos();
    let path = std::env::temp_dir().join(format!("{prefix}-{unique}"));
    fs::create_dir_all(&path).expect("create temp dir");
    path
}
