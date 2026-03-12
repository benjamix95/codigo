mod catalog;
mod handlers;
mod server;
mod shared_state;

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
