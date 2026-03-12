mod backend;
mod backend_tests;
mod batch_backend;
mod error;
mod mcp_models;
mod mcp_process;
mod protocol;
mod resource_prompt_backend;
mod service;
mod state;

fn main() {
    if let Err(error) = service::run_stdio_service() {
        eprintln!("mcp-lifecycle-backend-rust failed: {error}");
        std::process::exit(1);
    }
}
