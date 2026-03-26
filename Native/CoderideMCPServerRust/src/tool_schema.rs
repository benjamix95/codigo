use crate::tool_json_schema::{object_from_props, object_schema, SchemaProp};
use crate::tool_schema_verified_workflows::verified_workflow_schema;
use serde_json::Value;

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
    if let Some(schema) = verified_workflow_schema(name) {
        return schema;
    }
    match name {
        "coderide_read" => object_from_props(
            &[
                SchemaProp::with_desc("path", "File path (relative to workspace or absolute)."),
                SchemaProp::with_desc("offset", "Optional 1-based line offset when the host supports it."),
                SchemaProp::with_desc("limit", "Optional max lines to read when the host supports it."),
            ],
            &["path"],
        ),
        "coderide_list_dir" => object_from_props(
            &[SchemaProp::with_desc("path", "Directory to enumerate.")],
            &["path"],
        ),
        "coderide_read_range" => object_from_props(
            &[
                SchemaProp::with_desc("path", "File path."),
                SchemaProp::typed("start", "integer", "Start line (alias of start_line)."),
                SchemaProp::typed("end", "integer", "End line inclusive (alias of end_line)."),
                SchemaProp::typed("start_line", "integer", "Start line alias."),
                SchemaProp::typed("end_line", "integer", "End line alias."),
            ],
            &["path"],
        ),
        "coderide_glob" => object_from_props(
            &[
                SchemaProp::with_desc("pattern", "Glob pattern (e.g. **/*.swift)."),
                SchemaProp::with_desc("path", "Optional base directory."),
            ],
            &["pattern"],
        ),
        "coderide_grep" => object_from_props(
            &[
                SchemaProp::with_desc("query", "Regex or literal search (alias: pattern)."),
                SchemaProp::with_desc("pattern", "Alias of query."),
                SchemaProp::with_desc("pathScope", "Directory or file scope."),
                SchemaProp::with_desc("path", "Alias of pathScope."),
                SchemaProp::with_desc("fileType", "Extension filter e.g. swift, py."),
                SchemaProp::with_desc("glob", "Glob filter for paths."),
                SchemaProp::with_enum(
                    "output_mode",
                    "content (default), files_only, or count.",
                    &["content", "files_only", "count"],
                ),
                SchemaProp::typed("context_lines", "integer", "Lines of context around matches (max 10)."),
                SchemaProp::typed("case_sensitive", "boolean", "Case-sensitive regex when true."),
                SchemaProp::typed("multiline", "boolean", "Multiline regex mode when true."),
            ],
            &[],
        ),
        "coderide_find_files" => object_from_props(
            &[
                SchemaProp::with_desc("query", "File name search (alias: pattern)."),
                SchemaProp::with_desc("pattern", "Alias of query."),
                SchemaProp::with_desc("path", "Optional directory scope."),
                SchemaProp::with_desc("filePattern", "Optional path/glob filter."),
                SchemaProp::with_desc("extension", "Optional extension filter e.g. swift."),
            ],
            &[],
        ),
        "coderide_find_symbol" => object_from_props(
            &[
                SchemaProp::with_desc("query", "Symbol search string (alias: name)."),
                SchemaProp::with_desc("name", "Alias of query."),
                SchemaProp::with_desc("kind", "Optional symbol kind filter (class, function, …)."),
            ],
            &["query"],
        ),
        "coderide_find_references" => object_from_props(
            &[
                SchemaProp::with_desc("query", "Symbol to find references for (alias: name)."),
                SchemaProp::with_desc("name", "Alias of query."),
            ],
            &[],
        ),
        "coderide_file_outline" => object_from_props(
            &[SchemaProp::with_desc("path", "Source file path.")],
            &["path"],
        ),
        "coderide_codebase_search" => object_from_props(
            &[
                SchemaProp::with_desc("query", "Symbol or name search."),
                SchemaProp::with_desc("kind", "Optional symbol kind filter."),
                SchemaProp::with_desc("filePattern", "Optional file glob filter."),
                SchemaProp::with_desc("path", "Alias of filePattern for compatibility."),
            ],
            &["query"],
        ),
        "coderide_semantic_search" => object_from_props(
            &[
                SchemaProp::with_desc("query", "Natural language code search."),
                SchemaProp::with_desc("target_directories", "Comma-separated dirs (alias: targetDirectories, pathScope, path)."),
                SchemaProp::with_desc("targetDirectories", "Alias of target_directories."),
                SchemaProp::with_desc("pathScope", "Scope alias."),
                SchemaProp::with_desc("path", "Scope alias."),
                SchemaProp::with_desc("fileType", "Extension filter."),
                SchemaProp::typed("num_results", "integer", "Max hits (alias: limit)."),
                SchemaProp::typed("limit", "integer", "Alias of num_results."),
                SchemaProp::typed("min_confidence", "number", "Minimum score threshold."),
                SchemaProp::typed("show_scoring", "boolean", "Include scores in output when true."),
                SchemaProp::typed("strict_scope", "boolean", "Restrict to scope strictly when true."),
            ],
            &["query"],
        ),
        "coderide_read_lints" => object_from_props(
            &[
                SchemaProp::with_desc("path", "Optional path filter."),
                SchemaProp::with_desc("severity", "Optional minimum severity filter."),
                SchemaProp::typed("limit", "integer", "Max diagnostics to return."),
            ],
            &[],
        ),
        "coderide_diagnostics" => object_from_props(
            &[SchemaProp::with_desc("manager", "Optional host-specific diagnostics manager id.")],
            &[],
        ),
        "coderide_git_diff" => object_from_props(
            &[SchemaProp::with_desc("path", "Optional path scope for the diff.")],
            &[],
        ),
        "coderide_write" | "coderide_create_file" => object_from_props(
            &[
                SchemaProp::with_desc("path", "Destination file path."),
                SchemaProp::with_desc("content", "Full file contents."),
            ],
            &["path", "content"],
        ),
        "coderide_str_replace" => object_from_props(
            &[
                SchemaProp::with_desc("path", "File to edit."),
                SchemaProp::with_desc(
                    "old_string",
                    "Exact substring to replace once; add context lines if not unique.",
                ),
                SchemaProp::with_desc("new_string", "Replacement text."),
            ],
            &["path", "old_string", "new_string"],
        ),
        "coderide_regex_replace" => object_from_props(
            &[
                SchemaProp::with_desc("path", "File path."),
                SchemaProp::with_desc("pattern", "Regex pattern."),
                SchemaProp::with_desc("replacement", "Replacement (may use capture groups)."),
                SchemaProp::with_desc("flags", "Optional regex flags string."),
            ],
            &["path", "pattern", "replacement"],
        ),
        "coderide_todo_read" | "coderide_show_task_panel" => object_schema(&[], &[]),
        "coderide_todo_write" => object_from_props(
            &[
                SchemaProp::with_desc("title", "Single-item todo title (batch via todos)."),
                SchemaProp::with_desc("status", "Todo status string (host-defined; e.g. pending, in_progress, done)."),
                SchemaProp::with_desc("priority", "Optional priority string."),
                SchemaProp::with_desc("notes", "Optional notes."),
                SchemaProp::with_desc("activeForm", "Present-tense label for LiveCard."),
                SchemaProp::with_desc("linkedFiles", "JSON array or comma-separated file paths."),
                SchemaProp::with_desc("todos", "JSON array string of todo objects for batch update."),
            ],
            &[],
        ),
        "coderide_plan_create" => object_from_props(
            &[
                SchemaProp::with_desc("goal", "Plan title / primary objective (required)."),
                SchemaProp::with_desc(
                    "steps",
                    "JSON array string of steps (id, title, status, linked_files, …).",
                ),
                SchemaProp::with_desc("chosen_path", "Optional selected approach markdown."),
                SchemaProp::with_desc("conversation_id", "Conversation UUID."),
                SchemaProp::with_desc("replace_existing", "String true/false; replace current plan."),
            ],
            &["goal"],
        ),
        "coderide_plan_read" | "coderide_plan_history_read" => object_from_props(
            &[
                SchemaProp::with_desc("conversation_id", "Optional conversation UUID."),
                SchemaProp::with_desc("include_history", "String true/false for plan_read."),
                SchemaProp::with_desc("history_limit", "History depth (plan_read)."),
                SchemaProp::with_desc("limit", "Max snapshots (plan_history_read)."),
            ],
            &[],
        ),
        "coderide_plan_step_upsert" => object_from_props(
            &[
                SchemaProp::with_desc("step_id", "Step identifier."),
                SchemaProp::with_desc("status", "Step status string."),
                SchemaProp::with_desc("title", "Optional step title."),
                SchemaProp::with_desc("description", "Optional longer description."),
                SchemaProp::with_desc("target_file", "Primary file for this step."),
                SchemaProp::with_desc("linked_files", "JSON array of related paths."),
                SchemaProp::with_desc("depends_on", "JSON array of prerequisite step ids."),
                SchemaProp::with_desc("notes", "Optional notes."),
                SchemaProp::with_desc("conversation_id", "Optional conversation UUID."),
            ],
            &["step_id", "status"],
        ),
        "coderide_plan_step_update" => object_from_props(
            &[
                SchemaProp::with_desc("step_id", "Step id."),
                SchemaProp::with_desc("status", "New status."),
                SchemaProp::with_desc("title", "Optional title change."),
            ],
            &["step_id", "status"],
        ),
        "coderide_plan_step_batch_update" => object_from_props(
            &[
                SchemaProp::with_desc("updates", "JSON array of step patch objects."),
                SchemaProp::with_desc("conversation_id", "Optional conversation UUID."),
            ],
            &["updates"],
        ),
        "coderide_plan_step_reorder" => object_from_props(
            &[
                SchemaProp::with_desc("ordered_step_ids", "JSON array of step ids in order."),
                SchemaProp::with_desc("conversation_id", "Optional conversation UUID."),
            ],
            &["ordered_step_ids"],
        ),
        "coderide_plan_step_dependency_set" => object_from_props(
            &[
                SchemaProp::with_desc("step_id", "Step to update."),
                SchemaProp::with_desc("depends_on", "JSON array of prerequisite step ids."),
                SchemaProp::with_desc("conversation_id", "Optional conversation UUID."),
            ],
            &["step_id", "depends_on"],
        ),
        "coderide_plan_set_walkthrough" => object_from_props(
            &[
                SchemaProp::with_desc("markdown", "Final walkthrough body."),
                SchemaProp::with_desc("summary", "Optional short summary."),
                SchemaProp::with_desc("outcome", "Outcome: done, failed, or cancelled."),
                SchemaProp::with_desc("conversation_id", "Optional conversation UUID."),
            ],
            &["markdown"],
        ),
        "coderide_plan_diff" => object_from_props(
            &[
                SchemaProp::with_desc("from_snapshot_id", "Starting snapshot id."),
                SchemaProp::with_desc("to_snapshot_id", "Ending snapshot id (default latest)."),
                SchemaProp::with_desc("conversation_id", "Optional conversation UUID."),
            ],
            &["from_snapshot_id"],
        ),
        "coderide_plan_request_user_input" => object_from_props(
            &[
                SchemaProp::with_desc("questions", "JSON array of structured questions."),
                SchemaProp::with_desc("title", "Optional UI title."),
                SchemaProp::with_desc("phase", "Optional phase label."),
                SchemaProp::with_desc("round", "Optional round index."),
                SchemaProp::with_desc("context", "Optional blocker/context text."),
                SchemaProp::with_desc("conversation_id", "Optional conversation UUID."),
            ],
            &["questions"],
        ),
        "coderide_debug_set_phase" => object_schema(&[("phase", "string"), ("detail", "string")], &["phase"]),
        "coderide_debug_request_user" => object_schema(&[("kind", "string"), ("prompt", "string")], &["kind", "prompt"]),
        "coderide_debug_resolve" => object_schema(&[("summary", "string")], &["summary"]),
        "coderide_debug_log" => object_schema(
            &[
                ("severity", "string"),
                ("source", "string"),
                ("message", "string"),
                ("detail", "string"),
                ("category", "string"),
                ("run_id", "string"),
                ("hypothesis_id", "string"),
                ("data", "string"),
            ],
            &["severity", "source", "message"],
        ),
        "coderide_debug_session" => object_schema(&[("action", "string"), ("label", "string")], &["action"]),
        "coderide_debug_hypothesize" => object_schema(
            &[
                ("action", "string"),
                ("hypothesis_id", "string"),
                ("title", "string"),
                ("description", "string"),
                ("status", "string"),
                ("evidence", "string"),
                ("confidence", "string"),
                ("root_cause_type", "string"),
                ("related_files", "string"),
                ("related_tests", "string"),
            ],
            &["action"],
        ),
        "coderide_debug_context" => object_schema(&[("scope", "string")], &[]),
        "coderide_debug_mark" => object_schema(
            &[
                ("path", "string"),
                ("line", "string"),
                ("comment", "string"),
                ("code", "string"),
                ("type", "string"),
                ("expression", "string"),
                ("hypothesis_id", "string"),
            ],
            &["path", "line", "comment"],
        ),
        "coderide_debug_clean" => object_schema(
            &[("path", "string"), ("type", "string"), ("dry_run", "string"), ("hypothesis_id", "string")],
            &[],
        ),
        "coderide_debug_trace_analyze" => {
            object_schema(&[("error_text", "string"), ("error_type", "string"), ("context", "string")], &["error_text"])
        }
        "coderide_debug_instrument" => object_schema(
            &[
                ("path", "string"),
                ("line", "string"),
                ("type", "string"),
                ("expression", "string"),
                ("condition", "string"),
                ("hypothesis_id", "string"),
                ("label", "string"),
            ],
            &["path", "line", "type", "expression"],
        ),
        "coderide_debug_timeline" => object_schema(
            &[("filter", "string"), ("time_range", "string"), ("hypothesis_id", "string"), ("format", "string")],
            &[],
        ),
        "coderide_debug_snapshot" => {
            object_schema(&[("action", "string"), ("label", "string"), ("compare_with", "string")], &["action"])
        }
        "coderide_debug_test_check" => object_schema(
            &[
                ("scope", "string"),
                ("path", "string"),
                ("filter", "string"),
                ("hypothesis_id", "string"),
                ("timeout_ms", "string"),
            ],
            &["scope"],
        ),
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
        "coderide_skill" => object_schema(
            &[("skill", "string"), ("name", "string"), ("task", "string"), ("args", "string")],
            &[],
        ),
        "coderide_web_search" => object_schema(&[("query", "string"), ("explanation", "string")], &["query"]),
        "coderide_web_fetch" => object_schema(&[("url", "string")], &["url"]),
        "coderide_run_tests" => object_schema(&[("filter", "string"), ("scheme", "string")], &[]),
        "coderide_export_debug_bundle" => object_schema(&[("workspace_roots", "string")], &[]),
        _ => object_schema(&[], &[]),
    }
}

#[cfg(test)]
mod catalog_input_schema_tests {
    use super::input_schema_for;

    /// Tool che possono esporre `properties: {}`.
    const EMPTY_INPUT_SCHEMA_ALLOWLIST: &[&str] = &["coderide_todo_read", "coderide_show_task_panel"];

    #[test]
    fn every_catalog_tool_has_non_empty_properties_unless_allowlisted() {
        let raw = include_str!("tool_names.txt");
        for line in raw.lines().map(str::trim).filter(|l| !l.is_empty()) {
            if EMPTY_INPUT_SCHEMA_ALLOWLIST.contains(&line) {
                continue;
            }
            let schema = input_schema_for(line);
            let props = schema
                .get("properties")
                .and_then(|p| p.as_object())
                .unwrap_or_else(|| panic!("{line}: missing properties object"));
            assert!(!props.is_empty(), "{line}: input_schema has empty properties");
        }
    }
}
