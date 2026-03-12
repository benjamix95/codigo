# 2026-03-12 — Rust MCP server tranche 6 (runtime surface)

## Modifiche
- aggiunti nuovi moduli Rust nel server MCP locale:
  - [audit_tools.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/audit_tools.rs)
  - [diagnostics_tools.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/diagnostics_tools.rs)
  - [debug_tools.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/debug_tools.rs)
  - [web_tools.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/web_tools.rs)
  - [skill_tools.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/skill_tools.rs)
- il server MCP Rust ora copre anche:
  - `audit_*` supportati dal review core Rust
  - `semantic_search`
  - `git_diff`
  - `diagnostics`
  - `read_lints`
  - `debug_log`
  - `debug_query`
  - `debug_hypothesize`
  - `debug_timeline`
  - `debug_snapshot`
  - `debug_trace_analyze`
  - `debug_context`
  - `debug_test_check`
  - `debug_mark`
  - `debug_clean`
  - `debug_instrument`
  - `web_fetch`
  - `web_search`
  - `skill`
- aggiornato il wiring principale del server Rust per delegare questi domini ai nuovi moduli
- `Native/RustCore/src/lib.rs` espone ora `review_audit` come modulo pubblico per il riuso nel server MCP Rust

## Validazione eseguita
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml`

## Esito
- la superficie del server MCP Rust e' ora molto piu' vicina alla parita' del server Swift locale
- restano ancora da completare soprattutto review/security/bughunter full parity e la rimozione del lifecycle/session manager Swift
