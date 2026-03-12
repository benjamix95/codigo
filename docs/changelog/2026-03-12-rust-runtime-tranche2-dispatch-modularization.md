# 2026-03-12 - Tranche 2 runtime Rust: modularizzazione dispatch MCP

## Modifiche
- estratti nuovi moduli nel server MCP Rust:
  - `file_tools`
  - `ide_tools`
  - `subagent_tools`
  - `todo_tools`
- spostati `glob` e `grep` dentro `search_tools`, cosi' la famiglia search possiede tutto il perimetro di ricerca file/testo.
- spostati `debug_set_phase`, `debug_request_user` e `debug_resolve` nella famiglia `debug_tools`.
- ridotto `handlers.rs` a dispatcher centrale con routing esplicito e senza logica mista di famiglia.
- aggiunto `supports_tool_name(...)` con test `every_catalog_tool_has_a_dispatch_route`, che impedisce di aggiungere tool al catalogo senza route reale nel server.
- aggiornato `main.rs` per registrare i nuovi moduli del server Rust.

## Validazione eseguita
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml`

## Note
- resta un warning preesistente su `read_bughunter_snapshot` non usata in `shared_review_state.rs`; non fa parte di questa tranche.
- la validazione Apple-side via `xcodebuildmcp` non e' disponibile nell'ambiente corrente, quindi questa tranche resta confinata al server Rust.

## Esito
- il runtime MCP Rust ha ora famiglie di dispatch piu' nette e manutenibili
- il catalogo non puo' piu' divergere silenziosamente dal dispatcher senza far fallire i test
- il fallback generico rimane solo come ultima difesa per nomi esterni al catalogo
