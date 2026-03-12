# 2026-03-12 - Tranche 1 runtime Rust: freeze contratti e split FFI

## Modifiche
- spezzato `Native/RustCore/src/ffi.rs` in moduli di dominio sotto `Native/RustCore/src/ffi/`:
  - `common`
  - `search`
  - `review_core`
  - `review_pipeline`
  - `review_mcp`
  - `review_patch`
  - `review_persistence`
  - `review_command`
- mantenuti invariati i simboli FFI pubblici `review_core_*`, `solocode_semantic_*` e `solocode_free_buffer`, riducendo il rischio di regressione del bridge Swift.
- introdotto un catalogo tipizzato in `Native/CoderideMCPServerRust/src/catalog.rs` con:
  - `CATALOG_VERSION`
  - `CATALOG_TOOL_COUNT`
  - `ToolFamily`
  - `ToolSpec`
- congelato il catalogo MCP Rust sulla baseline corrente di `131` tool, con mapping famiglie/read-only/descrizione come source of truth della tranche.
- esteso `initialize` del server MCP Rust per esporre versione catalogo e conteggio tool nelle instructions di bootstrap.
- aggiunto test di contratto `Native/CoderideMCPServerRust/tests/catalog_contract.rs` sul path reale `tools/list`.

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml`

## Note
- `rustfmt` non e' disponibile nel toolchain locale (`stable-aarch64-apple-darwin`), quindi non e' stato possibile eseguire formatting automatico Rust in questa sessione.
- La validazione Apple-side con `xcodebuildmcp` non e' stata eseguita in questa tranche perche' il tool non e' disponibile nell'ambiente corrente.

## Esito
- il bridge Rust review e' ora modulare e pronto per le tranche successive senza un file FFI monolitico fuori policy
- il catalogo MCP Rust ha un baseline verificabile, utile per parity suite e cutover unico finale
- nessuna modifica e' stata fatta nelle aree Swift del panel gia' sporche nel worktree locale
