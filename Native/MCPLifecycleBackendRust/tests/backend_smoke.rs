use serde_json::{json, Value};
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn lifecycle_backend_manages_generic_mcp_servers() {
    let temp_root = make_temp_dir("mcp-lifecycle-backend");
    let cwd = temp_root.join("workspace");
    fs::create_dir_all(&cwd).expect("create workspace");
    let boot_file = temp_root.join("boot-count.txt");

    let mut child = BackendHarness::spawn();
    let fake_binary = env!("CARGO_BIN_EXE_fake-mcp-server").to_string();
    let server = json!({
        "id": "fake",
        "name": "Fake Server",
        "command": fake_binary,
        "args": [boot_file.display().to_string()],
        "cwd": cwd.display().to_string(),
        "env": { "MCP_FAKE_VALUE": "expected-env" }
    });

    let list = child.request("1", "list_servers", json!({ "servers": [server.clone()] }));
    assert!(list["ok"].as_bool().unwrap_or(false));
    assert_eq!(list["payload"]["servers"][0]["status"], "disconnected");

    let reconnect = child.request("2", "reconnect", json!({ "server": server }));
    assert!(reconnect["ok"].as_bool().unwrap_or(false));
    assert_eq!(reconnect["payload"]["status"], "ready");

    let health = child.request("3", "health", json!({}));
    assert_eq!(health["payload"]["states"]["fake"], "ready");

    let tools = child.request("4", "list_tools", json!({ "serverId": "fake" }));
    let tools_array = tools["payload"]["tools"].as_array().expect("tools array");
    assert!(tools_array.iter().any(|tool| tool["name"] == "echo"));
    assert!(tools_array.iter().all(|tool| tool["serverId"] == "fake"));

    let described = child.request(
        "4d",
        "describe_tool",
        json!({ "serverId": "fake", "toolName": "echo" }),
    );
    assert_eq!(described["payload"]["tool"]["name"], "echo");

    let resources = child.request("4r", "list_resources", json!({ "serverId": "fake" }));
    assert_eq!(
        resources["payload"]["resources"][0]["uri"],
        "fake://welcome"
    );

    let resource_content = child.request(
        "4rr",
        "read_resource",
        json!({ "serverId": "fake", "uri": "fake://welcome" }),
    );
    assert_eq!(
        resource_content["payload"]["contents"][0]["text"],
        "resource:fake://welcome"
    );

    let templates = child.request(
        "4rt",
        "list_resource_templates",
        json!({ "serverId": "fake" }),
    );
    assert_eq!(
        templates["payload"]["templates"][0]["uriTemplate"],
        "fake://template/{id}"
    );

    let prompts = child.request("4p", "list_prompts", json!({ "serverId": "fake" }));
    assert_eq!(prompts["payload"]["prompts"][0]["name"], "review_summary");

    let prompt = child.request(
        "4pg",
        "get_prompt",
        json!({ "serverId": "fake", "name": "review_summary", "arguments": { "topic": "scope" } }),
    );
    assert_eq!(
        prompt["payload"]["messages"][0]["content"]["text"],
        "summary:scope"
    );

    let echoed = child.request(
        "5",
        "call_tool",
        json!({ "serverId": "fake", "toolName": "echo", "arguments": { "message": "ciao" } }),
    );
    assert_eq!(echoed["payload"]["content"], "ciao");
    assert_eq!(echoed["payload"]["isError"], false);

    let failed = child.request(
        "6",
        "call_tool",
        json!({ "serverId": "fake", "toolName": "fail", "arguments": { "message": "boom" } }),
    );
    assert_eq!(failed["payload"]["isError"], true);
    assert_eq!(failed["payload"]["content"], "boom");

    let batch = child.request(
        "6b",
        "call_tools_batch",
        json!({
            "calls": [
                { "index": 0, "serverId": "fake", "toolName": "echo", "arguments": { "message": "batch-ok" } },
                { "index": 1, "serverId": "fake", "toolName": "fail", "arguments": { "message": "batch-fail" } }
            ]
        }),
    );
    assert_eq!(batch["payload"]["results"][0]["content"], "batch-ok");
    assert_eq!(batch["payload"]["results"][0]["isError"], false);
    assert_eq!(batch["payload"]["results"][1]["isError"], true);
    assert_eq!(batch["payload"]["results"][1]["content"], "batch-fail");

    let cwd_value = child.request(
        "7",
        "call_tool",
        json!({ "serverId": "fake", "toolName": "cwd", "arguments": {} }),
    );
    let actual_cwd = PathBuf::from(cwd_value["payload"]["content"].as_str().expect("cwd"));
    assert_eq!(
        fs::canonicalize(actual_cwd).expect("canonical actual"),
        fs::canonicalize(&cwd).expect("canonical expected")
    );

    let env_value = child.request(
        "8",
        "call_tool",
        json!({ "serverId": "fake", "toolName": "env_value", "arguments": {} }),
    );
    assert_eq!(env_value["payload"]["content"], "expected-env");

    let boot_before = child.request(
        "9",
        "call_tool",
        json!({ "serverId": "fake", "toolName": "boot_count", "arguments": {} }),
    );
    assert_eq!(boot_before["payload"]["content"], "1");

    let restart = child.request("10", "restart_server", json!({ "serverId": "fake" }));
    assert_eq!(restart["payload"]["status"], "ready");

    let boot_after = child.request(
        "11",
        "call_tool",
        json!({ "serverId": "fake", "toolName": "boot_count", "arguments": {} }),
    );
    assert_eq!(boot_after["payload"]["content"], "2");

    let shutdown = child.request("12", "shutdown_all", json!({}));
    assert_eq!(shutdown["payload"]["stopped"], 1);

    let health_after = child.request("13", "health", json!({}));
    assert_eq!(health_after["payload"]["states"]["fake"], "stopped");

    child.close();
}

#[test]
fn backend_reports_errors_for_unknown_server() {
    let mut child = BackendHarness::spawn();
    let response = child.request("1", "list_tools", json!({ "serverId": "missing" }));
    assert_eq!(response["ok"], false);
    assert!(response["error"]
        .as_str()
        .unwrap_or_default()
        .contains("unknown serverId"));
    child.close();
}

#[test]
fn lifecycle_backend_reuses_process_for_duplicate_server_configs() {
    let temp_root = make_temp_dir("mcp-lifecycle-dedup");
    let cwd = temp_root.join("workspace");
    fs::create_dir_all(&cwd).expect("create workspace");
    let boot_file = temp_root.join("boot-count.txt");
    let fake_binary = env!("CARGO_BIN_EXE_fake-mcp-server").to_string();

    let first = json!({
        "id": "fake-a",
        "name": "Fake Server",
        "command": fake_binary,
        "args": [boot_file.display().to_string()],
        "cwd": cwd.display().to_string(),
        "env": { "MCP_FAKE_VALUE": "expected-env" }
    });
    let second = json!({
        "id": "fake-b",
        "name": "Fake Server",
        "command": fake_binary,
        "args": [boot_file.display().to_string()],
        "cwd": cwd.display().to_string(),
        "env": { "MCP_FAKE_VALUE": "expected-env" }
    });

    let mut child = BackendHarness::spawn();
    let list = child.request(
        "1",
        "list_servers",
        json!({ "servers": [first.clone(), second.clone()] }),
    );
    assert!(list["ok"].as_bool().unwrap_or(false));
    assert_eq!(
        list["payload"]["servers"]
            .as_array()
            .map(|items| items.len()),
        Some(2)
    );

    let reconnect = child.request("2", "reconnect", json!({ "server": first }));
    assert!(reconnect["ok"].as_bool().unwrap_or(false));

    let boot_via_first = child.request(
        "3",
        "call_tool",
        json!({ "serverId": "fake-a", "toolName": "boot_count", "arguments": {} }),
    );
    assert_eq!(boot_via_first["payload"]["content"], "1");

    let boot_via_second = child.request(
        "4",
        "call_tool",
        json!({ "serverId": "fake-b", "toolName": "boot_count", "arguments": {} }),
    );
    assert_eq!(boot_via_second["payload"]["content"], "1");
    assert_eq!(boot_via_second["payload"]["serverId"], "fake-b");

    let shutdown = child.request("5", "shutdown_all", json!({}));
    assert_eq!(shutdown["payload"]["stopped"], 1);

    let health = child.request("6", "health", json!({}));
    assert_eq!(health["payload"]["states"]["fake-a"], "stopped");
    assert_eq!(health["payload"]["states"]["fake-b"], "stopped");

    child.close();
}

#[test]
fn lifecycle_backend_respawns_when_server_config_changes() {
    let temp_root = make_temp_dir("mcp-lifecycle-config-change");
    let cwd = temp_root.join("workspace");
    fs::create_dir_all(&cwd).expect("create workspace");
    let boot_file = temp_root.join("boot-count.txt");
    let fake_binary = env!("CARGO_BIN_EXE_fake-mcp-server").to_string();

    let initial = json!({
        "id": "fake-config",
        "name": "Fake Server",
        "command": fake_binary,
        "args": [boot_file.display().to_string()],
        "cwd": cwd.display().to_string(),
        "env": { "MCP_FAKE_VALUE": "alpha" }
    });
    let updated = json!({
        "id": "fake-config",
        "name": "Fake Server",
        "command": fake_binary,
        "args": [boot_file.display().to_string()],
        "cwd": cwd.display().to_string(),
        "env": { "MCP_FAKE_VALUE": "beta" }
    });

    let mut child = BackendHarness::spawn();
    let list = child.request("1", "list_servers", json!({ "servers": [initial.clone()] }));
    assert!(list["ok"].as_bool().unwrap_or(false));

    let reconnect = child.request("2", "reconnect", json!({ "server": initial }));
    assert!(reconnect["ok"].as_bool().unwrap_or(false));

    let first_env = child.request(
        "3",
        "call_tool",
        json!({ "serverId": "fake-config", "toolName": "env_value", "arguments": {} }),
    );
    assert_eq!(first_env["payload"]["content"], "alpha");

    let first_boot = child.request(
        "4",
        "call_tool",
        json!({ "serverId": "fake-config", "toolName": "boot_count", "arguments": {} }),
    );
    assert_eq!(first_boot["payload"]["content"], "1");

    let refresh = child.request("5", "list_servers", json!({ "servers": [updated] }));
    assert!(refresh["ok"].as_bool().unwrap_or(false));

    let second_env = child.request(
        "6",
        "call_tool",
        json!({ "serverId": "fake-config", "toolName": "env_value", "arguments": {} }),
    );
    assert_eq!(second_env["payload"]["content"], "beta");

    let second_boot = child.request(
        "7",
        "call_tool",
        json!({ "serverId": "fake-config", "toolName": "boot_count", "arguments": {} }),
    );
    assert_eq!(second_boot["payload"]["content"], "2");

    child.close();
}

#[test]
fn lifecycle_backend_acknowledges_server_initiated_requests() {
    let temp_root = make_temp_dir("mcp-lifecycle-server-request");
    let cwd = temp_root.join("workspace");
    fs::create_dir_all(&cwd).expect("create workspace");
    let boot_file = temp_root.join("boot-count.txt");
    let fake_binary = env!("CARGO_BIN_EXE_fake-mcp-server").to_string();

    let server = json!({
        "id": "fake-request",
        "name": "Fake Server Request",
        "command": fake_binary,
        "args": [boot_file.display().to_string()],
        "cwd": cwd.display().to_string(),
        "env": {
            "MCP_FAKE_VALUE": "expected-env",
            "MCP_FAKE_EMIT_SERVER_REQUEST_ON_LIST": "1"
        }
    });

    let mut child = BackendHarness::spawn();
    let list = child.request("1", "list_servers", json!({ "servers": [server.clone()] }));
    assert!(list["ok"].as_bool().unwrap_or(false));

    let tools = child.request("2", "list_tools", json!({ "server": server }));
    assert!(tools["ok"].as_bool().unwrap_or(false));

    let status = child.request(
        "3",
        "call_tool",
        json!({ "serverId": "fake-request", "toolName": "server_request_status", "arguments": {} }),
    );
    assert_eq!(status["payload"]["content"], "acknowledged");

    child.close();
}

struct BackendHarness {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
}

impl BackendHarness {
    fn spawn() -> Self {
        let mut child = Command::new(env!("CARGO_BIN_EXE_mcp-lifecycle-backend-rust"))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .expect("spawn backend");
        let stdin = child.stdin.take().expect("stdin");
        let stdout = child.stdout.take().expect("stdout");
        Self {
            child,
            stdin,
            stdout: BufReader::new(stdout),
        }
    }

    fn request(&mut self, id: &str, op: &str, payload: Value) -> Value {
        write_request(&mut self.stdin, id, op, payload);
        read_response(&mut self.stdout)
    }

    fn close(&mut self) {
        self.child.kill().ok();
        let _ = self.child.wait();
    }
}

fn write_request(stdin: &mut ChildStdin, id: &str, op: &str, payload: Value) {
    let request = json!({ "id": id, "op": op, "payload": payload });
    let encoded = serde_json::to_string(&request).expect("encode request");
    stdin.write_all(encoded.as_bytes()).expect("write request");
    stdin.write_all(b"\n").expect("write newline");
    stdin.flush().expect("flush request");
}

fn read_response(stdout: &mut BufReader<ChildStdout>) -> Value {
    let mut line = String::new();
    stdout.read_line(&mut line).expect("read response");
    serde_json::from_str(line.trim()).expect("decode response")
}

fn make_temp_dir(prefix: &str) -> PathBuf {
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("time")
        .as_nanos();
    let path = std::env::temp_dir().join(format!("{prefix}-{stamp}"));
    fs::create_dir_all(&path).expect("create temp dir");
    path
}
