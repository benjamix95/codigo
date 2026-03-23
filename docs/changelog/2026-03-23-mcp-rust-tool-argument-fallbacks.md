# 2026-03-23 — MCP rust tool argument fallbacks

## Modifiche
- `coderide_codebase_search` ora ricava una query fallback da `path`, `file`, `filePattern` o `pattern` quando `query` manca
- `bughunter_cancel_run` e gli altri action tool bughunter usano il run attivo come fallback quando `run_id` non e' esplicitato
- ricompilato `coderide-mcp-server-rust` e terminati i processi vecchi per forzare il respawn del server aggiornato

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml review_mcp::bughunter -- --nocapture`
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml search_tools -- --nocapture`
- `cargo build --manifest-path Native/CoderideMCPServerRust/Cargo.toml`
