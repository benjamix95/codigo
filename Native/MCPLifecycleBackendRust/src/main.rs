mod backend;
mod error;
mod mcp_process;
mod protocol;
mod service;
mod state;

fn main() {
    if let Err(error) = service::run_stdio_service() {
        eprintln!("mcp-lifecycle-backend-rust failed: {error}");
        std::process::exit(1);
    }
}
