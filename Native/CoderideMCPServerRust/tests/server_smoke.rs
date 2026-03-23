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

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 3,
            "method": "resources/list"
        }),
    );
    let resources = read_message(&mut child);
    assert_eq!(resources["result"]["resources"], json!([]));

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 4,
            "method": "resources/templates/list"
        }),
    );
    let templates = read_message(&mut child);
    assert_eq!(templates["result"]["resourceTemplates"], json!([]));

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
fn plan_create_without_conversation_id_bootstraps_new_plan_context() {
    let home = make_temp_dir("rust-mcp-home");
    let workspace = make_temp_dir("rust-mcp-workspace");
    let mut child = spawn_server(&home, &workspace);
    initialize(&mut child);

    write_message(
        child.stdin.as_mut().expect("stdin"),
        json!({
            "jsonrpc": "2.0",
            "id": 210,
            "method": "tools/call",
            "params": {
                "name": "coderide_plan_create",
                "arguments": {
                    "goal": "Bootstrap plan context",
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
            "id": 211,
            "method": "tools/call",
            "params": {
                "name": "coderide_plan_read",
                "arguments": {
                    "include_history": true,
                    "history_limit": 5
                }
            }
        }),
    );
    let read = read_message(&mut child);
    let read_text = read["result"]["content"][0]["text"].as_str().expect("plan read text");
    let read_json: Value = serde_json::from_str(read_text).expect("plan read json");
    let conversation_id = read_json["conversation_id"].as_str().expect("conversation id");
    assert_eq!(read_json["snapshot"]["goal"], "Bootstrap plan context");
    assert_eq!(read_json["snapshot"]["conversationId"], conversation_id);
    assert_eq!(conversation_id.len(), 36);
    assert!(conversation_id.chars().all(|ch| ch.is_ascii_hexdigit() || ch == '-'));

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

#[test]
fn editing_tools_work() {
    let home = make_temp_dir("rust-mcp-home");
    let workspace = make_temp_dir("rust-mcp-workspace");
    let mut child = spawn_server(&home, &workspace);
    initialize(&mut child);

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":40,"method":"tools/call",
        "params":{"name":"coderide_create_file","arguments":{"path":"Created.swift","content":"struct Created {}\n"}}
    }));
    let created = read_message(&mut child);
    assert!(created["result"]["content"][0]["text"].as_str().unwrap_or("").contains("Created"));
    assert_eq!(
        fs::read_to_string(workspace.join("Created.swift")).expect("created file"),
        "struct Created {}\n"
    );

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":41,"method":"tools/call",
        "params":{"name":"coderide_write","arguments":{"path":"Created.swift","content":"struct Created { let value = 1 }\n"}}
    }));
    let wrote = read_message(&mut child);
    assert!(wrote["result"]["content"][0]["text"].as_str().unwrap_or("").contains("Edit"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":42,"method":"tools/call",
        "params":{"name":"coderide_str_replace","arguments":{"path":"Created.swift","old_string":"let value = 1","new_string":"let value = 2"}}
    }));
    let replaced = read_message(&mut child);
    assert!(replaced["result"]["content"][0]["text"].as_str().unwrap_or("").contains("str_replace"));
    assert!(fs::read_to_string(workspace.join("Created.swift")).expect("replaced file").contains("value = 2"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":43,"method":"tools/call",
        "params":{"name":"coderide_regex_replace","arguments":{"path":"Created.swift","pattern":"value = 2","replacement":"value = 3"}}
    }));
    let regex = read_message(&mut child);
    assert!(regex["result"]["content"][0]["text"].as_str().unwrap_or("").contains("regex_replace"));
    assert!(fs::read_to_string(workspace.join("Created.swift")).expect("regex file").contains("value = 3"));
    terminate(child);
}

#[test]
fn diagnostics_and_audit_tools_work() {
    let home = make_temp_dir("rust-mcp-home");
    let workspace = make_temp_dir("rust-mcp-workspace");
    fs::write(
        workspace.join("Cargo.toml"),
        "[package]\nname = \"demo\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
    )
    .expect("write cargo");
    fs::create_dir_all(workspace.join("src")).expect("mkdir src");
    fs::write(workspace.join("src").join("lib.rs"), "pub fn demo() {}\n").expect("write rust file");
    fs::write(workspace.join("Security.swift"), "let digest = md5(password)\n").expect("write audit file");

    let mut child = spawn_server(&home, &workspace);
    initialize(&mut child);

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":50,"method":"tools/call",
        "params":{"name":"coderide_audit_security_crypto","arguments":{"scope_files":["Security.swift"]}}
    }));
    let audit = read_message(&mut child);
    assert!(audit["result"]["content"][0]["text"].as_str().unwrap_or("").contains("audit_security_crypto"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":51,"method":"tools/call",
        "params":{"name":"coderide_diagnostics","arguments":{"manager":"cargo"}}
    }));
    let diagnostics = read_message(&mut child);
    assert!(diagnostics["result"]["content"][0]["text"].as_str().is_some());

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":52,"method":"tools/call",
        "params":{"name":"coderide_read_lints","arguments":{}}
    }));
    let read_lints = read_message(&mut child);
    assert!(read_lints["result"]["content"][0]["text"].as_str().is_some());

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":53,"method":"tools/call",
        "params":{"name":"coderide_git_diff","arguments":{}}
    }));
    let git_diff = read_message(&mut child);
    assert!(git_diff["result"]["content"][0]["text"].as_str().is_some());
    terminate(child);
}

#[test]
fn debug_and_skill_tools_work() {
    let home = make_temp_dir("rust-mcp-home");
    let workspace = make_temp_dir("rust-mcp-workspace");
    let skill_dir = home.join(".codex").join("skills").join("demo-skill");
    fs::create_dir_all(&skill_dir).expect("mkdir skill");
    fs::write(skill_dir.join("SKILL.md"), "# Demo\nbody-content\n").expect("write skill");

    let mut child = spawn_server(&home, &workspace);
    initialize(&mut child);

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":60,"method":"tools/call",
        "params":{"name":"coderide_debug_log","arguments":{"severity":"info","source":"test","message":"hello debug"}}
    }));
    let debug_log = read_message(&mut child);
    assert_eq!(debug_log["result"]["content"][0]["text"].as_str(), Some("OK — debug log entry recorded"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":61,"method":"tools/call",
        "params":{"name":"coderide_debug_query","arguments":{"search":"hello"}}
    }));
    let debug_query = read_message(&mut child);
    assert!(debug_query["result"]["content"][0]["text"].as_str().unwrap_or("").contains("hello debug"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":62,"method":"tools/call",
        "params":{"name":"coderide_debug_request_user","arguments":{"kind":"question","prompt":"What OS?"}}
    }));
    let request_question = read_message(&mut child);
    assert_eq!(
        request_question["result"]["content"][0]["text"].as_str(),
        Some("OK \u{2014} debug user request queued (question)")
    );

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":63,"method":"tools/call",
        "params":{"name":"coderide_debug_request_user","arguments":{"kind":"reproduce","prompt":"Steps please"}}
    }));
    let request_reproduce = read_message(&mut child);
    assert_eq!(
        request_reproduce["result"]["content"][0]["text"].as_str(),
        Some("OK \u{2014} debug user request queued (reproduce)")
    );

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":64,"method":"tools/call",
        "params":{"name":"coderide_debug_request_user","arguments":{"kind":"fix_confirmation","prompt":"Confirm fix"}}
    }));
    let request_fix = read_message(&mut child);
    assert_eq!(
        request_fix["result"]["content"][0]["text"].as_str(),
        Some("OK \u{2014} debug user request queued (fix_confirmation)")
    );

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":65,"method":"tools/call",
        "params":{"name":"coderide_debug_request_user","arguments":{"kind":"invalid_kind","prompt":"test"}}
    }));
    let request_invalid = read_message(&mut child);
    assert!(
        request_invalid["result"]["content"][0]["text"]
            .as_str()
            .unwrap_or("")
            .contains("invalid kind")
    );

    write_message(child.stdin.as_mut().expect("stdin"), json!({
        "jsonrpc":"2.0","id":66,"method":"tools/call",
        "params":{"name":"coderide_skill","arguments":{"skill":"demo-skill","task":"run checks"}}
    }));
    let skill = read_message(&mut child);
    assert!(skill["result"]["content"][0]["text"].as_str().unwrap_or("").contains("Demo"));
    terminate(child);
}

#[test]
fn review_security_and_bughunter_tools_work() {
    let home = make_temp_dir("rust-mcp-home");
    let workspace = make_temp_dir("rust-mcp-workspace");
    Command::new("/usr/bin/git").arg("init").arg("-q").current_dir(&workspace).output().expect("git init");
    Command::new("/usr/bin/git").args(["config", "user.email", "review-tests@example.com"]).current_dir(&workspace).output().expect("git email");
    Command::new("/usr/bin/git").args(["config", "user.name", "Review Tests"]).current_dir(&workspace).output().expect("git name");
    fs::write(workspace.join("README.md"), "# Demo\n").expect("write readme");
    Command::new("/usr/bin/git").args(["add", "README.md"]).current_dir(&workspace).output().expect("git add");
    Command::new("/usr/bin/git").args(["commit", "-qm", "initial"]).current_dir(&workspace).output().expect("git commit");
    fs::create_dir_all(workspace.join("Sources")).expect("mkdir sources");
    fs::write(workspace.join("Sources").join("Auth.swift"), "func auth() {}\n").expect("write auth");

    let shared = home.join("Library").join("Application Support").join("CoderIDE").join("mcp-shared");
    let review_dir = shared.join("code-review").join("sessions");
    let bughunter_dir = shared.join("bughunter").join("runs");
    fs::create_dir_all(&review_dir).expect("mkdir review");
    fs::create_dir_all(&bughunter_dir).expect("mkdir bughunter");
    let review_snapshot = json!({
        "sessionId":"review-1",
        "conversationId":"11111111-1111-1111-1111-111111111111",
        "phase":"fixing",
        "stage":"fixing",
        "statusSummary":"Review in progress",
        "workspacePath": workspace.display().to_string(),
        "scope":{"type":"uncommitted","files":["Sources/Auth.swift"]},
        "findings":[{"id":"security-1","severity":"critical","category":"security","origin":"securityAuditor","filePath":"Sources/Auth.swift","lineNumber":12,"message":"Missing authz check","status":"open"}],
        "candidates":[{"id":"candidate-1","severity":"warning","category":"correctness","origin":"bugHunter","filePath":"Sources/App.swift","lineNumber":7,"message":"Crash path","verificationStatus":"new"}],
        "patches":[{"id":"patch-1","findingId":"security-1","status":"verified","verifyStatus":"verified","validationStatus":"passed","diffPreview":"@@"}],
        "outcome":{"summary":"done","verifiedFindings":1,"falsePositives":0,"patchesReady":1,"patchesApplied":0,"prsOpened":0,"mergedPatches":0,"conflictsDetected":0,"manualActionRequired":false,"testsStatus":"passed"},
        "verifiedFindings":{"canonicalSnapshot":{"findings":{"bug-1":{"id":"bug-1","domain":"bug","title":"Crash in loader. path A","category":"correctness","confidence":0.96,"filePath":"Sources/Loader.swift","status":"verified"},"bug-2":{"id":"bug-2","domain":"bug","title":"Crash in loader. path B","category":"correctness","confidence":0.90,"filePath":"Sources/Loader.swift","status":"verified"}}}}
    });
    fs::write(review_dir.join("review-1.json"), serde_json::to_vec_pretty(&review_snapshot).unwrap()).expect("write review");
    let bughunter_snapshot = json!({
        "runId":"run-1","reviewSessionId":"review-1","sourceKind":"uncommitted","triggerKind":"manual","gitRoot":workspace.display().to_string(),"status":"running","verifiedFindingsCount":2,"candidateFindingsCount":1,"lastRevalidationVerdict":"fixed_verified","securityGateReady":true,"lastUpdatedAt":"2026-03-12T12:00:00Z"
    });
    fs::write(bughunter_dir.join("run-1.json"), serde_json::to_vec_pretty(&bughunter_snapshot).unwrap()).expect("write bughunter");

    let mut child = spawn_server(&home, &workspace);
    initialize(&mut child);

    write_message(child.stdin.as_mut().expect("stdin"), json!({"jsonrpc":"2.0","id":70,"method":"tools/call","params":{"name":"coderide_review_status","arguments":{"session_id":"review-1"}}}));
    let review_status = read_message(&mut child);
    assert!(review_status["result"]["content"][0]["text"].as_str().unwrap_or("").contains("session_id: review-1"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({"jsonrpc":"2.0","id":71,"method":"tools/call","params":{"name":"coderide_review_findings","arguments":{"session_id":"review-1"}}}));
    let review_findings = read_message(&mut child);
    assert!(review_findings["result"]["content"][0]["text"].as_str().unwrap_or("").contains("redacted-swift-file-"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({"jsonrpc":"2.0","id":71_5,"method":"tools/call","params":{"name":"coderide_review_diff_summary","arguments":{"session_id":"review-1"}}}));
    let review_diff = read_message(&mut child);
    let review_diff_text = review_diff["result"]["content"][0]["text"].as_str().unwrap_or("");
    assert!(review_diff_text.contains("Sources/Auth.swift"));
    assert!(review_diff_text.contains("+1 / -0"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({"jsonrpc":"2.0","id":72,"method":"tools/call","params":{"name":"coderide_review_apply_patch","arguments":{"session_id":"review-1","finding_id":"security-1"}}}));
    let apply_patch = read_message(&mut child);
    assert!(apply_patch["result"]["content"][0]["text"].as_str().unwrap_or("").contains("queued"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({"jsonrpc":"2.0","id":73,"method":"tools/call","params":{"name":"coderide_security_status","arguments":{"session_id":"review-1"}}}));
    let security_status = read_message(&mut child);
    assert!(security_status["result"]["content"][0]["text"].as_str().unwrap_or("").contains("security_gate_ready"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({"jsonrpc":"2.0","id":74,"method":"tools/call","params":{"name":"coderide_bughunter_status","arguments":{"run_id":"run-1"}}}));
    let bughunter_status = read_message(&mut child);
    assert!(bughunter_status["result"]["content"][0]["text"].as_str().unwrap_or("").contains("verified_findings_count: 2"));

    write_message(child.stdin.as_mut().expect("stdin"), json!({"jsonrpc":"2.0","id":75,"method":"tools/call","params":{"name":"coderide_bughunter_explain_cluster","arguments":{"run_id":"run-1"}}}));
    let cluster = read_message(&mut child);
    assert!(cluster["result"]["content"][0]["text"].as_str().unwrap_or("").contains("cluster_title: Crash in loader"));
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
