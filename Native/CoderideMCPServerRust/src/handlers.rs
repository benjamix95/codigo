use crate::audit_tools;
use crate::debug_tools;
use crate::diagnostics_tools;
use crate::edit_tools;
use crate::file_tools;
use crate::ide_tools;
use crate::plan_state;
use crate::review_tools;
use crate::search_tools;
use crate::skill_tools;
use crate::subagent_tools;
use crate::support_workflow_tools;
use crate::todo_tools;
use crate::web_tools;
use app_core_protocol::mcp::{CallToolResult, ToolCallParams};
use std::path::Path;

pub fn handle_tool_call(workspace: &Path, params: ToolCallParams) -> CallToolResult {
    let arguments = params.arguments.unwrap_or_default();
    if let Some(result) = audit_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = diagnostics_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = support_workflow_tools::handle(params.name.as_str(), workspace, &arguments)
    {
        return result;
    }
    if let Some(result) = debug_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = edit_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = file_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = ide_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = search_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = subagent_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = todo_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = web_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = skill_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = review_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    match params.name.as_str() {
        "coderide_plan_create" => wrap(plan_state::create_snapshot(&arguments)),
        "coderide_plan_read" => wrap(plan_state::read_latest(&arguments)),
        "coderide_plan_history_read" => wrap(plan_state::read_history(&arguments)),
        "coderide_plan_step_update" => wrap(plan_state::step_update(&arguments)),
        "coderide_plan_step_upsert" => wrap(plan_state::step_upsert(&arguments)),
        "coderide_plan_step_batch_update" => wrap(plan_state::step_batch_update(&arguments)),
        "coderide_plan_step_reorder" => wrap(plan_state::step_reorder(&arguments)),
        "coderide_plan_step_dependency_set" => wrap(plan_state::step_dependency_set(&arguments)),
        "coderide_plan_set_walkthrough" => wrap(plan_state::set_walkthrough(&arguments)),
        "coderide_plan_diff" => wrap(plan_state::diff(&arguments)),
        "coderide_plan_request_user_input" => wrap(plan_state::request_user_input(&arguments)),
        name => CallToolResult::error(format!("tool not yet migrated to rust server: {name}")),
    }
}

#[cfg_attr(not(test), allow(dead_code))]
pub fn supports_tool_name(name: &str) -> bool {
    audit_tools::handle(name, Path::new("."), &Default::default()).is_some()
        || diagnostics_tools::handle(name, Path::new("."), &Default::default()).is_some()
        || support_workflow_tools::supports(name)
        || debug_tools::handle(name, Path::new("."), &Default::default()).is_some()
        || edit_tools::handle(name, Path::new("."), &Default::default()).is_some()
        || file_tools::supports(name)
        || ide_tools::supports(name)
        || search_tools::supports(name)
        || subagent_tools::supports(name)
        || todo_tools::supports(name)
        || web_tools::handle(name, Path::new("."), &Default::default()).is_some()
        || skill_tools::handle(name, Path::new("."), &Default::default()).is_some()
        || review_tools::handle(name, Path::new("."), &Default::default()).is_some()
        || matches!(
            name,
            "coderide_activate_debug_mode"
                | "coderide_plan_create"
                | "coderide_plan_read"
                | "coderide_plan_history_read"
                | "coderide_plan_step_update"
                | "coderide_plan_step_upsert"
                | "coderide_plan_step_batch_update"
                | "coderide_plan_step_reorder"
                | "coderide_plan_step_dependency_set"
                | "coderide_plan_set_walkthrough"
                | "coderide_plan_diff"
                | "coderide_plan_request_user_input"
        )
}

fn wrap(result: Result<String, String>) -> CallToolResult {
    match result {
        Ok(message) => CallToolResult::text(message),
        Err(message) => CallToolResult::error(message),
    }
}

#[cfg(test)]
mod tests {
    use super::supports_tool_name;

    #[test]
    fn every_catalog_tool_has_a_dispatch_route() {
        for spec in crate::catalog::tool_specs() {
            assert!(
                supports_tool_name(spec.name),
                "tool senza route handler: {}",
                spec.name
            );
        }
    }
}
