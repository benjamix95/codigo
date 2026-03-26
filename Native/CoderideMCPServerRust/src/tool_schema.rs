use serde_json::{json, Map, Value};

pub fn input_schema_for(name: &str) -> Value {
    if name.starts_with("coderide_audit_") {
        return object_schema(
            &[
                ("scope_files", "string"),
                ("scopeFiles", "string"),
                ("path", "string"),
                ("profile", "string"),
                ("file", "string"),
                ("message", "string"),
                ("line", "string"),
                ("evidence", "string"),
            ],
            &[],
        );
    }
    match name {
        "coderide_read" => object_schema(&[("path", "string")], &["path"]),
        "coderide_list_dir" => object_schema(&[("path", "string")], &["path"]),
        "coderide_read_range" => object_schema(
            &[("path", "string"), ("start", "integer"), ("end", "integer"), ("start_line", "integer"), ("end_line", "integer")],
            &["path"],
        ),
        "coderide_glob" => object_schema(&[("pattern", "string"), ("path", "string")], &["pattern"]),
        "coderide_grep" => object_schema(
            &[
                ("query", "string"), ("pattern", "string"), ("pathScope", "string"), ("path", "string"),
                ("fileType", "string"), ("glob", "string"), ("context_lines", "integer"),
                ("case_sensitive", "boolean"), ("multiline", "boolean"), ("output_mode", "string"),
            ],
            &[],
        ),
        "coderide_find_files" => object_schema(
            &[("query", "string"), ("pattern", "string"), ("path", "string"), ("filePattern", "string"), ("extension", "string")],
            &[],
        ),
        "coderide_find_symbol" => object_schema(&[("query", "string"), ("name", "string"), ("kind", "string")], &["query"]),
        "coderide_find_references" => object_schema(&[("query", "string"), ("name", "string")], &[]),
        "coderide_file_outline" => object_schema(&[("path", "string")], &["path"]),
        "coderide_codebase_search" => object_schema(
            &[("query", "string"), ("kind", "string"), ("filePattern", "string"), ("path", "string")],
            &["query"],
        ),
        "coderide_semantic_search" => object_schema(
            &[
                ("query", "string"), ("target_directories", "string"), ("targetDirectories", "string"),
                ("pathScope", "string"), ("path", "string"), ("fileType", "string"), ("num_results", "integer"),
                ("limit", "integer"), ("min_confidence", "number"), ("show_scoring", "boolean"),
                ("strict_scope", "boolean"),
            ],
            &["query"],
        ),
        "coderide_read_lints" => object_schema(&[("path", "string"), ("severity", "string"), ("limit", "integer")], &[]),
        "coderide_diagnostics" => object_schema(&[("manager", "string")], &[]),
        "coderide_git_diff" => object_schema(&[("path", "string")], &[]),
        "coderide_write" | "coderide_create_file" => object_schema(&[("path", "string"), ("content", "string")], &["path", "content"]),
        "coderide_str_replace" => object_schema(&[("path", "string"), ("old_string", "string"), ("new_string", "string")], &["path", "old_string", "new_string"]),
        "coderide_regex_replace" => object_schema(&[("path", "string"), ("pattern", "string"), ("replacement", "string"), ("flags", "string")], &["path", "pattern", "replacement"]),
        "coderide_todo_read" | "coderide_show_task_panel" => object_schema(&[], &[]),
        "coderide_todo_write" => object_schema(
            &[
                ("title", "string"), ("status", "string"), ("priority", "string"), ("notes", "string"),
                ("activeForm", "string"), ("linkedFiles", "string"), ("todos", "string"),
            ],
            &[],
        ),
        "coderide_plan_create" => object_schema(
            &[("goal", "string"), ("steps", "string"), ("chosen_path", "string"), ("conversation_id", "string"), ("replace_existing", "string")],
            &["goal"],
        ),
        "coderide_plan_read" | "coderide_plan_history_read" => object_schema(
            &[("conversation_id", "string"), ("include_history", "string"), ("history_limit", "string"), ("limit", "string")],
            &[],
        ),
        "coderide_plan_step_upsert" => object_schema(
            &[
                ("step_id", "string"), ("status", "string"), ("title", "string"), ("description", "string"),
                ("target_file", "string"), ("linked_files", "string"), ("depends_on", "string"),
                ("notes", "string"), ("conversation_id", "string"),
            ],
            &["step_id", "status"],
        ),
        "coderide_plan_step_update" => object_schema(&[("step_id", "string"), ("status", "string"), ("title", "string")], &["step_id", "status"]),
        "coderide_plan_step_batch_update" => object_schema(&[("updates", "string"), ("conversation_id", "string")], &["updates"]),
        "coderide_plan_step_reorder" => object_schema(&[("ordered_step_ids", "string"), ("conversation_id", "string")], &["ordered_step_ids"]),
        "coderide_plan_step_dependency_set" => object_schema(&[("step_id", "string"), ("depends_on", "string"), ("conversation_id", "string")], &["step_id", "depends_on"]),
        "coderide_plan_set_walkthrough" => object_schema(&[("markdown", "string"), ("summary", "string"), ("outcome", "string"), ("conversation_id", "string")], &["markdown"]),
        "coderide_plan_diff" => object_schema(&[("from_snapshot_id", "string"), ("to_snapshot_id", "string"), ("conversation_id", "string")], &["from_snapshot_id"]),
        "coderide_plan_request_user_input" => object_schema(
            &[("questions", "string"), ("title", "string"), ("phase", "string"), ("round", "string"), ("context", "string"), ("conversation_id", "string")],
            &["questions"],
        ),
        "coderide_debug_set_phase" => object_schema(&[("phase", "string"), ("detail", "string")], &["phase"]),
        "coderide_debug_request_user" => object_schema(&[("kind", "string"), ("prompt", "string")], &["kind", "prompt"]),
        "coderide_debug_resolve" => object_schema(&[("summary", "string")], &["summary"]),
        "coderide_debug_log" => object_schema(
            &[
                ("severity", "string"), ("source", "string"), ("message", "string"),
                ("detail", "string"), ("category", "string"), ("run_id", "string"),
                ("hypothesis_id", "string"), ("data", "string"),
            ],
            &["severity", "source", "message"],
        ),
        "coderide_debug_session" => object_schema(&[("action", "string"), ("label", "string")], &["action"]),
        "coderide_debug_hypothesize" => object_schema(
            &[
                ("action", "string"), ("hypothesis_id", "string"), ("title", "string"),
                ("description", "string"), ("status", "string"), ("evidence", "string"),
                ("confidence", "string"), ("root_cause_type", "string"),
                ("related_files", "string"), ("related_tests", "string"),
            ],
            &["action"],
        ),
        "coderide_debug_context" => object_schema(&[("scope", "string")], &[]),
        "coderide_debug_mark" => object_schema(
            &[("path", "string"), ("line", "string"), ("comment", "string"), ("code", "string"), ("type", "string"), ("expression", "string"), ("hypothesis_id", "string")],
            &["path", "line", "comment"],
        ),
        "coderide_debug_clean" => object_schema(
            &[("path", "string"), ("type", "string"), ("dry_run", "string"), ("hypothesis_id", "string")],
            &[],
        ),
        "coderide_debug_trace_analyze" => object_schema(&[("error_text", "string"), ("error_type", "string"), ("context", "string")], &["error_text"]),
        "coderide_debug_instrument" => object_schema(
            &[("path", "string"), ("line", "string"), ("type", "string"), ("expression", "string"), ("condition", "string"), ("hypothesis_id", "string"), ("label", "string")],
            &["path", "line", "type", "expression"],
        ),
        "coderide_debug_timeline" => object_schema(&[("filter", "string"), ("time_range", "string"), ("hypothesis_id", "string"), ("format", "string")], &[]),
        "coderide_debug_snapshot" => object_schema(&[("action", "string"), ("label", "string"), ("compare_with", "string")], &["action"]),
        "coderide_debug_test_check" => object_schema(&[("scope", "string"), ("path", "string"), ("filter", "string"), ("hypothesis_id", "string"), ("timeout_ms", "string")], &["scope"]),
        "coderide_activate_plan_mode" | "coderide_activate_debug_mode" => object_schema(&[("reason", "string")], &[]),
        "coderide_show_swarm_panel" => object_schema(&[("swarm_id", "string")], &[]),
        "coderide_policy_ack" => object_schema(&[("hash", "string")], &["hash"]),
        "coderide_mermaid_render" => object_schema(&[("code", "string"), ("title", "string")], &["code"]),
        "coderide_subagent_explorer"
        | "coderide_subagent_coder"
        | "coderide_subagent_debugger"
        | "coderide_subagent_reviewer"
        | "coderide_subagent_bugHunter"
        | "coderide_subagent_testWriter"
        | "coderide_subagent_docWriter"
        | "coderide_subagent_securityAuditor" => object_schema(&[("task", "string")], &["task"]),
        "coderide_skill" => object_schema(&[("skill", "string"), ("name", "string"), ("task", "string"), ("args", "string")], &[]),
        "coderide_web_search" => object_schema(&[("query", "string"), ("explanation", "string")], &["query"]),
        "coderide_web_fetch" => object_schema(&[("url", "string")], &["url"]),
        "coderide_run_tests" => object_schema(
            &[
                ("filter", "string"),
                ("scheme", "string"),
            ],
            &[],
        ),
        "coderide_export_debug_bundle" => object_schema(&[("workspace_roots", "string")], &[]),
        _ => object_schema(&[], &[]),
    }
}

fn object_schema(properties: &[(&str, &str)], required: &[&str]) -> Value {
    let mut props = Map::new();
    for (name, kind) in properties {
        props.insert((*name).to_string(), json!({ "type": kind }));
    }

    let required_values = required.iter().map(|value| Value::String((*value).to_string())).collect::<Vec<_>>();
    let mut schema = Map::new();
    schema.insert("type".to_string(), Value::String("object".to_string()));
    schema.insert("properties".to_string(), Value::Object(props));
    if !required_values.is_empty() {
        schema.insert("required".to_string(), Value::Array(required_values));
    }
    Value::Object(schema)
}
