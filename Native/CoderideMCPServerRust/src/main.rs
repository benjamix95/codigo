mod audit_tools;
mod catalog;
mod debug_tools;
mod diagnostics_tools;
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
mod todo_tools;
mod tool_schema;
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
                return PathBuf::from(value);
            }
        }
    }
    env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}
