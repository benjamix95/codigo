## 2026-03-23 - Rust MCP shared manager and config respawn hardening

- Il runtime persistente app-side ora usa `MCPSessionManager.shared` invece di istanziare un manager separato, riducendo la duplicazione dei backend `mcp-lifecycle-backend-rust`.
- Il registry MCP nativo normalizza in lower-case gli alias `coderide_*`, cosi' i tool mixed-case come `coderide_subagent_securityAuditor` restano raggiungibili dai nomi canonici normalizzati.
- `MCPLifecycleRustBackend` e `McpProcess` chiudono esplicitamente i processi figli anche nel teardown finale, riducendo il rischio di child orfani quando il transport viene smaltito.
- Aggiunta regressione Rust nel crate `MCPLifecycleBackendRust` che verifica il respawn del processo quando cambia la config osservabile del server mantenendo la stessa identity logica.
- Aggiunte regressioni runtime su `review_start`, `todo_write` e `plan_create` per mantenere osservabile il path MCP canonico quando il registry `coderide_*` e' caldo.

### Verifica eseguita

- `cargo test --manifest-path Native/MCPLifecycleBackendRust/Cargo.toml`
- `xcodebuild test -quiet -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/MCPRuntimeServiceTests`
- `xcodebuild test -quiet -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests/testCanonicalReviewStartPrefersCoderideAliasWhenRegistryIsWarm`
- `xcodebuild test -quiet -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests/testCanonicalWebSearchPrefersCoderideAliasWhenRegistryIsWarm`
