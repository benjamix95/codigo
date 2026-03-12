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
