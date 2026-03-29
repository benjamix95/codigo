# Rust MCP Tools Fix Batch - 2026-03-29

## Bug Fix Record
- Categoria: A/B mista
- Bug: compile break `debug_*`; hardening insufficiente `web_*`; clear/race in `todo_write`; lifecycle MCP fragile; `run_tests`/`debug_test_check` fragili; drift contract catalogo; cache semantica solo parziale; traversal nei debug file tools
- Sintomo: server Rust non buildabile in alcuni percorsi; fetch/search web non sicuri; clear TODO senza effetto; richieste MCP server-initiated ignorate; tool Xcode poco configurabili; test catalogo rosso; overhead evitabile in semantic search; file debug modificabili fuori workspace
- Impatto: stabilità, sicurezza e affidabilità ridotte nel catalogo MCP Rust
- Gravità: P0-P2
- Steps to reproduce:
  1. `cargo test -p coderide_mcp_server_rust`
  2. chiamare `coderide_todo_write` con `todos=""`
  3. chiamare `coderide_web_fetch` con `file:///etc/passwd`
  4. usare un fake MCP server che emette una server-request durante `tools/list`
- Risultato attuale prima del fix: compile error, clear finto, schemi web arbitrari, richieste MCP perse, contract test stale
- Risultato atteso: build stabile, TODO coerenti, hardening web, bridge MCP robusto, catalogo allineato
- Causa probabile: regressioni locali, validazione insufficiente, lock non uniformi, assunzioni troppo ottimistiche sul protocollo, numeri magici nei test
- Scope consentito: `Native/CoderideMCPServerRust/src/{debug_tools,web_tools,shared_state,support_workflow_tools,diagnostics_tools,tool_schema,file_lock,shared_review_state,review_tools,benchmark_tools_semantic}.rs`, `Native/CoderideMCPServerRust/tests/{catalog_contract,server_smoke}.rs`, `Native/MCPLifecycleBackendRust/src/{mcp_process,bin/fake_mcp_server}.rs`, `Native/MCPLifecycleBackendRust/tests/backend_smoke.rs`, `Native/AppCoreProtocol/src/main_chat_provider.rs`
- Non-scope: UI Swift e modifiche locali estranee al batch MCP Rust
- Moduli confinanti verificati: catalogo/schema tool, lifecycle smoke tests, server smoke tests, semantic benchmark helper
- Test aggiunti o aggiornati:
  - unit/regression test per `web_*`
  - unit test per `todo_write` parser/clear
  - unit test per helper `debug_*`
  - smoke test lifecycle per server-request acknowledgment
  - smoke test server per clear TODO
  - contract test catalogo allineato al catalogo reale
- Strategia di fix minimo: patch mirate e additive, nessun revert delle modifiche locali non mie
- Verifica post-fix:
  - `cargo test -p coderide_mcp_server_rust`
  - `cargo test -p mcp_lifecycle_backend_rust`
  - `cargo clippy -p coderide_mcp_server_rust --all-targets --no-deps -- -D warnings`
  - `cargo clippy -p mcp_lifecycle_backend_rust --all-targets -- -D warnings`
- Commit previsto: commit dedicato al batch di fix MCP Rust
