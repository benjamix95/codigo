# 2026-03-12 — Rust MCP server tranche 4 (search e read-only)

## Modifiche
- aggiunto il modulo Rust [search_tools.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/search_tools.rs) per isolare i tool MCP read-only di ricerca
- il server MCP Rust ora gestisce anche:
  - `coderide_read_range`
  - `coderide_find_files`
  - `coderide_find_symbol`
  - `coderide_find_references`
  - `coderide_file_outline`
  - `coderide_codebase_search`
- le implementazioni attuali sono deterministiche e filesystem-based:
  - `read_range` legge porzioni di file
  - `find_files` usa `rg --files`
  - `find_symbol` / `find_references` usano regex su sorgenti
  - `file_outline` estrae outline leggero per righe dichiarative
  - `codebase_search` usa ricerca testuale read-only
- l’handler principale MCP Rust ora delega il blocco search/read-only al nuovo modulo dedicato

## Validazione eseguita
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml`
- smoke test di processo estesi in `server_smoke.rs`

## Esito
- la copertura Rust lato MCP è salita anche sui tool di esplorazione codice più comuni
- il cutover totale resta comunque non completo: i tool mutanti e diverse aree di runtime MCP sono ancora da migrare
