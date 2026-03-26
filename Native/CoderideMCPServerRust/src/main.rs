mod audit_tools;
mod catalog;
mod tool_descriptions;
mod debug_tools;
mod diagnostics_tools;
mod mcp_index_cache;
mod edit_tools;
mod file_lock;
mod file_tools;
mod handlers;
mod ide_tools;
mod plan_state;
mod review_tools;
mod search_tools;
mod server;
mod shared_review_state;
mod shared_state;
mod skill_tools;
mod subagent_tools;
mod support_workflow_tools;
mod todo_tools;
mod tool_json_schema;
mod tool_schema;
mod tool_schema_verified_workflows;
mod tool_schema_workflow_bughunter;
mod tool_schema_workflow_review;
mod tool_schema_workflow_security;
mod tool_schema_workflow_shared;
mod web_tools;

use server::{run_stdio_server, ServerConfig};
use std::env;
use std::path::PathBuf;

fn main() {
    let config = ServerConfig {
        workspace: resolve_workspace(),
    };
    if let Err(error) = run_stdio_server(config) {
        eprintln!("coderide-mcp-server-rust failed: {error}");
        std::process::exit(1);
    }
}

fn resolve_workspace() -> PathBuf {
    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        if arg == "--workspace" {
            if let Some(value) = args.next() {
                let trimmed = value.trim();
                if trimmed.is_empty() || trimmed == "." {
                    if let Some(override_path) = workspace_override_from_env() {
                        return override_path;
                    }
                }
                return PathBuf::from(trimmed);
            }
        }
    }
    if let Some(override_path) = workspace_override_from_env() {
        return override_path;
    }
    env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

fn workspace_override_from_env() -> Option<PathBuf> {
    let value = env::var("SOLOCODE_WORKSPACE_PATH").ok()?;
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    Some(PathBuf::from(trimmed))
}
