# P1 - Il cutover Rust del runtime tool non aveva un catalogo congelato ne' una parity baseline verificabile

## Bug Fix Record
- Categoria: A
- Bug: la migrazione verso `Native/CoderideMCPServerRust` non aveva un catalogo tool versionato e verificato; `tool_names.txt` esisteva, ma non c'era un contratto congelato che legasse nome, read-only hint, descrizione e famiglie del catalogo.
- Sintomo: ogni tranche poteva aggiungere o cambiare tool senza una parity baseline unica; il rischio era arrivare al cutover finale con drift silenzioso tra `tools/list`, handler reali e aspettative del runtime Swift.
- Impatto: alto rischio di regressioni nel cutover unico del `UnifiedToolRuntime`, con mismatch tra catalogo MCP, policy read-only e surface area effettivamente migrata.
- Gravita': alta, perche' tocca il boundary condiviso di tutti gli strumenti.
- Steps to reproduce:
  1. Avviare il server `coderide-mcp-server-rust`.
  2. Chiamare `tools/list`.
  3. Osservare che il server espone i tool, ma senza una suite che congeli conteggio catalogo, coverage metadata e famiglie minime del runtime.
- Risultato attuale: il catalogo Rust non aveva una parity matrix minima e i cambiamenti di catalogo potevano sfuggire ai test.
- Risultato atteso: il catalogo MCP Rust deve essere congelato per tranche, con versione esplicita, conteggio tool noto e test su metadata/annotazioni.
- Causa probabile: il focus delle tranche precedenti era sulla pipeline review e sui bridge FFI, non sul contratto completo del runtime tool.
- Scope consentito:
  - `Native/CoderideMCPServerRust/src/catalog.rs`
  - `Native/CoderideMCPServerRust/src/server.rs`
  - `Native/CoderideMCPServerRust/tests/*`
  - documentazione `docs/bugs`, `docs/changelog`, `docs/migration`
- Non-scope:
  - cutover finale del runtime Swift
  - migrazione completa di tutti gli handler ancora stub
  - UI panel SwiftUI
- Moduli confinanti da verificare:
  - `Native/CoderideMCPServerRust/src/handlers.rs`
  - `Native/CoderideMCPServerRust/tests/server_smoke.rs`
  - `Native/CoderideMCPServerRust/src/server.rs`
- Test da aggiungere o aggiornare:
  - test unitari catalogo su version freeze, conteggio tool e coverage famiglie
  - test integrazione `tools/list` su conteggio e annotazioni
- Strategia di fix minimo:
  - introdurre `ToolSpec` tipizzato come source of truth runtime
  - congelare `CATALOG_VERSION` e `CATALOG_TOOL_COUNT`
  - aggiungere parity test sul path `tools/list`
- Verifica post-fix:
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml`
- Commit previsto: `test(runtime): freeze rust tool catalog contract`
