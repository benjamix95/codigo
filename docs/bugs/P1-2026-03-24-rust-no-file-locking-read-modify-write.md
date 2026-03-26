# P1 — Nessun file locking su cicli read-modify-write nel Rust MCP server

## Bug Fix Record
- Categoria: B - Importante
- Bug: Le operazioni read-modify-write sui file di stato condiviso (`shared_review_state.rs`, `debug_tools.rs`, `shared_state.rs`) non usano alcun file locking. Crash mid-write corrompono i file. Letture concorrenti possono leggere dati parziali.
- Sintomo: File JSON troncati o corrotti dopo crash. Dati persi dopo write concorrenti da processi diversi.
- Impatto: Corruzione stato, perdita dati.
- Gravità: P1
- Scope consentito: `shared_review_state.rs` (`write_json`), `debug_tools.rs` (`write_store`), `shared_state.rs` (`write_json_array`).
- Strategia di fix minimo: Implementare atomic write (write-to-temp + rename) e advisory file lock (`flock`) per le operazioni critiche. Il lato Swift già usa questo pattern.
- Commit previsto: `fix(mcp-rust): add atomic write and file locking for shared state`
