# 2026-03-11 — Review MCP e shared-state: queue/index e handler read-only portati su Rust

## Modifiche
- aggiunto il nuovo dominio Rust `review_mcp` con:
  - modelli request/response MCP
  - queue review e bughunter
  - indice sessioni review
  - handler review/security/bughunter per status/findings/list/history/cluster
- estesi gli entrypoint FFI in `Native/RustCore/src/ffi.rs`:
  - `review_core_mcp_handle_tool`
  - `review_core_security_handle_tool`
  - `review_core_bughunter_handle_tool`
  - `review_core_mcp_enqueue_command`
  - `review_core_mcp_claim_commands`
  - `review_core_mcp_mark_command`
  - `review_core_mcp_command_heartbeat`
  - `review_core_mcp_read_index`
- introdotti adapter Swift nel core:
  - `MCPSharedState+RustReviewQueue`
  - `MCPSharedState+RustBugHunterQueue`
  - `MCPSharedState+RustReviewIndex`
  - `ReviewMCPRustModels`
  - `ReviewMCPRustBridge`
- `MCPSharedState+CodeReviewCommands` e `MCPSharedState+BugHunterCommands` usano ora Rust per enqueue/claim/mark/heartbeat, mantenendo Swift solo per persistenza file/lock
- `MCPSharedState+PersistenceBridge.buildCodeReviewIndex` usa ora Rust per l’indice review
- aggiunto `CodeReviewRustHandlerSupport` nel server MCP
- instradati via Rust i tool read-only e di stato:
  - `review_status`
  - `review_findings`
  - `review_list_sessions`
  - `review_get_outcome`
  - `security_status`
  - `security_findings`
  - `bughunter_status`
  - `bughunter_findings`
  - `bughunter_run_history`
  - `bughunter_explain_cluster`
- le azioni mutate restano shell Swift, ma passano sulle nuove queue Rust-backed

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `scripts/build_rust_search_backend.sh`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSharedCodeReviewCommandsTests -only-testing:CoderEngineTests/MCPSharedCodeReviewSnapshotStoreTests -only-testing:CoderEngineTests/MCPSharedBugHunterCommandsTests -only-testing:CoderEngineTests/CodeReviewHandlerTests -only-testing:CoderEngineTests/SecurityHandlerTests -only-testing:CoderEngineTests/BugHunterHandlerTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests`

## Esito
- le queue review/bughunter e l’indice review non dipendono più da business rules Swift
- i principali handler MCP read-only del panel passano dal core Rust
- il command loop app-side review resta compatibile e continua a funzionare
- resta aperto il lavoro sui benchmark MCP/shared-state dedicati, documentato come bug P2
