use app_core_protocol::mcp::ToolDefinition;
use crate::tool_schema::input_schema_for;

const TOOL_NAMES: &str = include_str!("tool_names.txt");
pub const CATALOG_VERSION: &str = "2026-03-26";
pub const CATALOG_TOOL_COUNT: usize = 138;

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum ToolFamily {
    Audit,
    BugHunter,
    Codebase,
    Diagnostics,
    Debug,
    Edit,
    File,
    Git,
    Plan,
    Policy,
    Review,
    Search,
    Security,
    Skill,
    Subagent,
    Todo,
    Ui,
    Web,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ToolSpec {
    pub name: &'static str,
    pub family: ToolFamily,
    pub description: String,
    pub read_only: bool,
}

pub fn all_tools() -> Vec<ToolDefinition> {
    tool_specs()
        .into_iter()
        .map(|spec| {
            ToolDefinition::with_schema(
                spec.name,
                Some(spec.description.clone()),
                spec.read_only,
                input_schema_for(spec.name),
            )
        })
        .collect()
}

pub fn tool_specs() -> Vec<ToolSpec> {
    TOOL_NAMES.lines().map(str::trim).filter(|line| !line.is_empty()).map(tool_spec).collect()
}

fn tool_spec(name: &'static str) -> ToolSpec {
    ToolSpec {
        name,
        family: family_for(name),
        description: crate::tool_descriptions::description_for(name),
        read_only: is_read_only(name),
    }
}

fn family_for(name: &str) -> ToolFamily {
    if name.starts_with("coderide_audit_") {
        ToolFamily::Audit
    } else if name.starts_with("coderide_bughunter_") {
        ToolFamily::BugHunter
    } else if name.starts_with("coderide_diagnostics")
        || name == "coderide_export_debug_bundle"
        || name == "coderide_run_tests"
    {
        ToolFamily::Diagnostics
    } else if name.starts_with("coderide_debug_") {
        ToolFamily::Debug
    } else if name.starts_with("coderide_plan_")
        || name == "coderide_activate_plan_mode"
        || name == "coderide_activate_debug_mode"
    {
        ToolFamily::Plan
    } else if name.starts_with("coderide_review_") {
        ToolFamily::Review
    } else if name.starts_with("coderide_security_") {
        ToolFamily::Security
    } else if name.starts_with("coderide_skill") {
        ToolFamily::Skill
    } else if name.starts_with("coderide_subagent_") {
        ToolFamily::Subagent
    } else if name.starts_with("coderide_todo_") {
        ToolFamily::Todo
    } else if name.starts_with("coderide_web_") {
        ToolFamily::Web
    } else {
        match name {
            "coderide_codebase_search"
            | "coderide_file_outline"
            | "coderide_find_files"
            | "coderide_find_references"
            | "coderide_find_symbol"
            | "coderide_read_lints"
            | "coderide_semantic_search" => ToolFamily::Codebase,
            "coderide_create_file"
            | "coderide_regex_replace"
            | "coderide_str_replace"
            | "coderide_write" => ToolFamily::Edit,
            "coderide_git_diff" => ToolFamily::Git,
            "coderide_glob" | "coderide_grep" => ToolFamily::Search,
            "coderide_mermaid_render" | "coderide_policy_ack" => ToolFamily::Policy,
            "coderide_list_dir" | "coderide_read" | "coderide_read_range" => ToolFamily::File,
            "coderide_show_swarm_panel" | "coderide_show_task_panel" => ToolFamily::Ui,
            _ => ToolFamily::Policy,
        }
    }
}

fn is_read_only(name: &str) -> bool {
    if name.starts_with("coderide_audit_") {
        return true;
    }
    matches!(
        name,
        "coderide_read"
            | "coderide_list_dir"
            | "coderide_read_range"
            | "coderide_glob"
            | "coderide_grep"
            | "coderide_find_files"
            | "coderide_find_symbol"
            | "coderide_find_references"
            | "coderide_file_outline"
            | "coderide_codebase_search"
            | "coderide_semantic_search"
            | "coderide_read_lints"
            | "coderide_git_diff"
            | "coderide_debug_context"
            | "coderide_debug_query"
            | "coderide_debug_timeline"
            | "coderide_debug_trace_analyze"
            | "coderide_todo_read"
            | "coderide_plan_read"
            | "coderide_plan_diff"
            | "coderide_plan_history_read"
            | "coderide_review_status"
            | "coderide_review_findings"
            | "coderide_review_list_sessions"
            | "coderide_review_diff_summary"
            | "coderide_review_preview_patch"
            | "coderide_review_get_outcome"
            | "coderide_security_status"
            | "coderide_security_findings"
            | "coderide_security_preview_patch"
            | "coderide_bughunter_status"
            | "coderide_bughunter_findings"
            | "coderide_bughunter_run_history"
            | "coderide_bughunter_explain_cluster"
            | "coderide_web_fetch"
            | "coderide_web_search"
    )
}

#[cfg(test)]
mod tests {
    use super::{all_tools, tool_specs, CATALOG_TOOL_COUNT, CATALOG_VERSION, ToolFamily};
    use std::collections::HashSet;

    #[test]
    fn catalog_version_is_frozen_for_tranche() {
        assert_eq!(CATALOG_VERSION, "2026-03-26");
    }

    #[test]
    fn every_tool_name_has_exactly_one_spec() {
        let specs = tool_specs();
        let unique_names: HashSet<_> = specs.iter().map(|spec| spec.name).collect();
        assert_eq!(specs.len(), unique_names.len());
        assert_eq!(specs.len(), CATALOG_TOOL_COUNT);
        assert!(specs.iter().all(|spec| !spec.description.trim().is_empty()));
    }

    #[test]
    fn all_tools_expose_read_only_annotations() {
        let tools = all_tools();
        assert_eq!(tools.len(), CATALOG_TOOL_COUNT);
        assert!(tools.iter().all(|tool| tool.annotations.is_some()));
        assert!(tools.iter().all(|tool| tool.description.is_some()));
    }

    #[test]
    fn catalog_covers_core_families() {
        let specs = tool_specs();
        let families: HashSet<_> = specs.iter().map(|spec| spec.family).collect();
        assert!(families.contains(&ToolFamily::Review));
        assert!(families.contains(&ToolFamily::Plan));
        assert!(families.contains(&ToolFamily::Debug));
        assert!(families.contains(&ToolFamily::File));
        assert!(families.contains(&ToolFamily::Web));
    }
}
