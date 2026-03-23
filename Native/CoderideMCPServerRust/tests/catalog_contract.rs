use serde_json::{json, Value};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn tools_list_matches_frozen_catalog_size_and_annotations() {
    let home = make_temp_dir("rust-mcp-home");
    let workspace = make_temp_dir("rust-mcp-workspace");
    let mut child = spawn_server(&home, &workspace);

    initialize(&mut child);
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
    assert_eq!(tools.len(), 131);
    assert!(tools.iter().all(|tool| tool["description"].is_string()));
    assert!(tools.iter().all(|tool| tool["annotations"]["readOnlyHint"].is_boolean()));
    assert!(tools.iter().any(|tool| tool["name"] == "coderide_review_start"));
    assert!(tools.iter().any(|tool| tool["name"] == "coderide_web_search"));

    terminate(child);
}

#[test]
fn core_tools_expose_non_empty_input_schemas() {
    let home = make_temp_dir("rust-mcp-home");
    let workspace = make_temp_dir("rust-mcp-workspace");
    let mut child = spawn_server(&home, &workspace);

    initialize(&mut child);
    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 22,
            "method": "tools/list"
        }),
    );

    let listed = read_message(&mut child);
    let tools = listed["result"]["tools"].as_array().expect("tools array");

    let read = tools.iter().find(|tool| tool["name"] == "coderide_read").expect("read tool");
    assert_eq!(read["inputSchema"]["required"], json!(["path"]));
    assert!(read["inputSchema"]["properties"]["path"].is_object());

    let todo_write = tools.iter().find(|tool| tool["name"] == "coderide_todo_write").expect("todo_write tool");
    assert!(todo_write["inputSchema"]["properties"]["title"].is_object());
    assert!(todo_write["inputSchema"]["properties"]["todos"].is_object());

    let plan_create = tools.iter().find(|tool| tool["name"] == "coderide_plan_create").expect("plan_create tool");
    assert_eq!(plan_create["inputSchema"]["required"], json!(["goal"]));
    assert!(plan_create["inputSchema"]["properties"]["steps"].is_object());

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
    let init = read_message(child);
    assert_eq!(init["result"]["serverInfo"]["name"], "coderide-tools-rust");

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        }),
    );
}

fn spawn_server(home: &PathBuf, workspace: &PathBuf) -> std::process::Child {
    Command::new("cargo")
        .args(["run", "--quiet", "--manifest-path", "Native/CoderideMCPServerRust/Cargo.toml", "--", "--workspace"])
        .arg(workspace)
        .current_dir("/Users/benjaminstoica/SoloCode")
        .env("HOME", home)
        .env("CODERIDE_HOME", home)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("spawn rust server")
}

fn write_message(stdin: &mut std::process::ChildStdin, payload: Value) {
    let encoded = serde_json::to_string(&payload).expect("encode payload");
    stdin.write_all(encoded.as_bytes()).expect("write payload");
    stdin.write_all(b"\n").expect("write newline");
    stdin.flush().expect("flush stdin");
}

fn read_message(child: &mut std::process::Child) -> Value {
    let stdout = child.stdout.as_mut().expect("stdout");
    let mut line = Vec::new();
    loop {
        let mut byte = [0_u8; 1];
        stdout.read_exact(&mut byte).expect("read stdout");
        if byte[0] == b'\n' {
            break;
        }
        line.push(byte[0]);
    }
    serde_json::from_slice(&line).expect("decode jsonrpc line")
}

fn terminate(mut child: std::process::Child) {
    let _ = child.kill();
    let _ = child.wait();
}

fn make_temp_dir(label: &str) -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock")
        .as_nanos();
    let path = std::env::temp_dir().join(format!("{label}-{nonce}"));
    std::fs::create_dir_all(&path).expect("create temp dir");
    path
}
