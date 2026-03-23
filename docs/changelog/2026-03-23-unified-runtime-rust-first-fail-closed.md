## 2026-03-23 - Unified runtime rust-first fail-closed

- `UnifiedToolRuntime` non lascia piu' scivolare nel branch Swift locale i tool gia' classificati come Rust-first quando il registry MCP e' caldo ma il route Rust specifico manca.
- Il failure mode e' ora esplicito:
  - `error_code = mcp_unavailable`
  - `is_mcp = true`
- Aggiunta regressione in `UnifiedToolRuntimeMCPConsistencyTests` per coprire il caso “registry caldo, alias mancante”.

### Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests`

### Avanzamento
- Avanzamento complessivo del cutover Rust-first: **95%**

### Note
- Restano fuori da questo batch la rimozione fisica dei branch Swift locali ancora presenti nel `switch` e gli ultimi residui app-side/code panel non ancora drenati.
