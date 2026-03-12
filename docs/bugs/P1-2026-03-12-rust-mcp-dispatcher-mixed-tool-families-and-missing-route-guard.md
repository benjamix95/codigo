# P1 - Il dispatcher MCP Rust concentrava famiglie eterogenee e non bloccava il drift del catalogo verso il fallback

## Bug Fix Record
- Categoria: A
- Bug: `Native/CoderideMCPServerRust/src/handlers.rs` conteneva ancora logica mista per file, IDE ack, todo, subagent, grep/glob e plan dispatch, senza una guardia che verificasse che ogni tool del catalogo avesse una route reale.
- Sintomo: l'aggiunta o modifica di tool nel catalogo poteva lasciare route incomplete nel dispatcher centrale; il fallback `"tool not yet migrated to rust server"` restava l'ultima rete di sicurezza invece che un errore da bloccare in test.
- Impatto: rischio alto di regressioni silenziose nel cutover del runtime Rust, con surface area MCP dichiarata ma non confinata per famiglie stabili.
- Gravita': alta, perche' tocca il boundary di tutti gli strumenti registrati dal server MCP Rust.
- Steps to reproduce:
  1. Aggiungere o rinominare un tool nel catalogo Rust.
  2. Non aggiornare `handlers.rs` in modo coerente.
  3. Eseguire `tools/list` e poi una `tools/call` sul tool non instradato.
  4. Osservare il fallback generico invece di una route coperta da modulo dedicato.
- Risultato attuale: il dispatcher centrale aggregava famiglie multiple e non aveva un test che imponesse la copertura completa del catalogo.
- Risultato atteso: ogni famiglia deve vivere in un modulo dedicato e il server deve fallire in test se un tool del catalogo non ha dispatch.
- Causa probabile: migrazione incrementale del server MCP con logica residua lasciata nel dispatcher principale.
- Scope consentito:
  - `Native/CoderideMCPServerRust/src/handlers.rs`
  - `Native/CoderideMCPServerRust/src/{file_tools,ide_tools,subagent_tools,todo_tools,search_tools,debug_tools}.rs`
  - `Native/CoderideMCPServerRust/src/main.rs`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - cutover del facade Swift `UnifiedToolRuntime`
  - UI del panel
  - modifica dei contratti MCP pubblici
- Moduli confinanti da verificare:
  - `server_smoke.rs`
  - `catalog_contract.rs`
  - `catalog.rs`
- Test da aggiungere o aggiornare:
  - unit test `every_catalog_tool_has_a_dispatch_route`
  - smoke del server MCP invariato
- Strategia di fix minimo:
  - estrarre moduli dedicati per file, IDE, subagent e todo
  - spostare `glob`/`grep` nella famiglia search
  - mantenere `handlers.rs` come puro dispatcher
  - bloccare il drift del catalogo con un test di coverage route
- Verifica post-fix:
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml`
- Commit previsto: `refactor(rust-runtime): modularize mcp dispatch families`
