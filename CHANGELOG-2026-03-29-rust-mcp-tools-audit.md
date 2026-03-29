# Changelog - 2026-03-29 - Rust MCP Tools Audit

## Cosa ho fatto
- Ho censito tutti i tool MCP Rust pubblicati dal server in `Native/CoderideMCPServerRust/src/tool_names.txt`.
- Ho mappato il dispatch Rust tra catalogo, handler, moduli `*_tools`, lifecycle backend e RustCore review bridge.
- Ho eseguito verifiche statiche e dinamiche sui crate Rust MCP.
- Ho scritto un report in docs con inventario completo, bug trovati, priorità, ottimizzazioni e hardening.

## Documenti aggiunti
- `docs/bugs/P0-2026-03-29-rust-mcp-tools-audit.md`

## Verifiche eseguite
- `cargo test -p coderide_mcp_server_rust`
  Esito: test unitari ok, contract test fallito per drift sul numero tool pubblicati.
- `cargo test -p mcp_lifecycle_backend_rust`
  Esito: ok.
- `cargo test -p solocode_rust_core ffi::review_mcp`
  Esito: ok.
- `cargo clippy -p coderide_mcp_server_rust --all-targets -- -D warnings`
  Esito: interrotto da errore `too_many_arguments` in `AppCoreProtocol`.
- `cargo clippy -p mcp_lifecycle_backend_rust --all-targets -- -D warnings`
  Esito: interrotto dallo stesso errore in `AppCoreProtocol`.

## Findings principali registrati
- Compile break locale nei tool `debug_*`.
- Hardening mancante nei tool web.
- Bug logico e di concorrenza in `todo_write`.
- Gestione JSON-RPC fragile nel lifecycle backend.
- Routing Xcode/iOS fragile in `debug_test_check` e `run_tests`.
- Cache semantica solo parzialmente efficace.
- Test di contratto catalogo rimasto a 142 tool invece di 143.

## Note
- Non ho modificato il codice applicativo dei tool: ho limitato l’intervento alla documentazione dell’audit, per evitare di mescolare review e fix nello stesso passaggio.
- Ho lasciato intatte le modifiche locali non mie presenti nel worktree.
