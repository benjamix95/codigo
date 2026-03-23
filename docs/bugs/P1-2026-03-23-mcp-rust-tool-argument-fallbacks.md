# P1 — 2026-03-23 — MCP Rust tools troppo fragili su argomenti parziali nel feed review

## Bug Fix Record
- Categoria: A — Critico
- Bug:
  - `coderide_codebase_search` falliva con `Missing 'query' argument` anche quando il caller passava un path/file context valido
  - `coderide_bughunter_cancel_run` falliva con `Error: 'run_id' is required` anche quando esisteva gia' un run attivo nel contesto
- Sintomo: nel feed review comparivano card rosse per tool MCP reali, non per errori applicativi dell'utente
- Impatto: rumore operativo nel pannello, perdita di fiducia nel path MCP Rust unico
- Gravita': alta
- Steps to reproduce:
  1. invocare `codebase_search` con solo `path` o `filePattern`
  2. invocare `bughunter_cancel_run` in presenza di un run attivo ma senza `run_id`
  3. osservare gli errori rossi nel feed
- Risultato attuale: hard-fail su argomento mancante anche quando il contesto permette un fallback ragionevole
- Risultato atteso: i tool devono usare fallback sicuri e context-aware prima di fallire
- Causa probabile:
  - validazione troppo rigida nel server MCP Rust e nel core review_mcp
- Scope consentito:
  - `Native/CoderideMCPServerRust/src/search_tools.rs`
  - `Native/RustCore/src/review_mcp/bughunter.rs`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - redesign delle API tool
  - modifica del significato semantico dei tool oltre i fallback minimi
- Moduli confinanti da verificare:
  - test unit Rust `review_mcp::bughunter`
  - test server `search_tools`
- Test da aggiungere o aggiornare:
  - fallback `codebase_search` da `path` a query derivata
  - fallback `bughunter_cancel_run` al run attivo
- Strategia di fix minimo:
  - derivare `query` dal basename/stem di `path|file|filePattern|pattern`
  - usare `active_bughunter_snapshot.run_id` quando `run_id` manca
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml review_mcp::bughunter -- --nocapture`
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml search_tools -- --nocapture`
  - `cargo build --manifest-path Native/CoderideMCPServerRust/Cargo.toml`
- Commit previsto: `fix(mcp-rust): add safe argument fallbacks for review tools`
