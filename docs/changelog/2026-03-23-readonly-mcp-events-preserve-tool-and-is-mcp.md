## 2026-03-23 - Read-only MCP events preserve tool and is_mcp

- Esteso `IDEStateSyntheticEventFactory` ai path read-only Rust-owned:
  - `review_status`
  - `review_findings`
  - `review_get_outcome`
  - `security_status`
  - `security_findings`
  - `bughunter_status`
  - `bughunter_findings`
  - `bughunter_run_history`
  - `bughunter_explain_cluster`
- I synthetic payload MCP ora preservano `tool` canonico e `is_mcp`, quindi il layer UI/test non perde più il marker Rust-first su questi tool.
- Aggiunte regressioni in `UnifiedToolRuntimeMCPConsistencyTests` per verificare il route MCP-first e la propagazione del metadata sui tool read-only.

### Validazione eseguita
- `cargo test --manifest-path Native/MCPLifecycleBackendRust/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests`

### Note
- Il fallback Swift del parser `review_findings` nel panel review non è stato drenato in questa tranche: il bridge Rust del panel non offre ancora parità sufficiente per togliere il fallback senza regressioni.
- Avanzamento batch dopo questa slice: **70%** del percorso obbligatorio Rust-first.
