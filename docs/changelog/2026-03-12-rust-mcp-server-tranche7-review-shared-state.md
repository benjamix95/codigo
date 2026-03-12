# 2026-03-12 — Rust MCP server tranche 7 (review/security/bughunter shared state)

## Modifiche
- aggiunti:
  - [shared_review_state.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/shared_review_state.rs)
  - [review_tools.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/review_tools.rs)
- il server MCP Rust ora legge lo shared state persistito per:
  - snapshot code review
  - snapshot bughunter
  - queue commands review
  - queue commands bughunter
- `review_*`, `security_*` e `bughunter_*` non usano più payload vuoti lato server Rust:
  - costruiscono richieste con snapshot reali
  - leggono findings/status/outcome da stato persistito
  - enqueuano comandi nei file condivisi quando l’azione è mutante
  - seedano il path `bughunter_start` con queue reale
- `coderide-mcp-server` è stato invertito:
  - default su server Rust
  - override di rollback su legacy Swift via `SOLOCODE_USE_SWIFT_MCP_SERVER=1`

## Validazione eseguita
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests/testCallToolRichRecordsMetrics -only-testing:CoderEngineTests/MCPSessionManagerTests/testSubagentExplorerToolReturnsImmediateAck`

## Esito
- il server MCP Rust locale copre ora il catalogo tool del server Swift anche sul dominio review/security/bughunter con shared state reale
- il lavoro residuo della migrazione si sposta da “parità MCP locale” a “ownership runtime/app core ancora Swift”
