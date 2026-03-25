# P0 — solocode_rust_core: modulo ffi::common privato blocca build

## Bug Fix Record
- Categoria: A - Critico
- Bug: il modulo `ffi::common` in `RustCore/src/ffi/mod.rs` e dichiarato `mod common` (privato), ma `trigram/ffi.rs` tenta di usare `crate::ffi::common::with_raw_json_input`. Questo blocca `cargo build` dell'intero workspace.
- Sintomo: `error[E0603]: module 'common' is private` — build fallita per tutto il workspace Rust.
- Impatto: impossibile compilare qualsiasi crate che dipende da `solocode_rust_core`, incluso `coderide_mcp_server_rust`.
- Gravita: P0 — build bloccata
- Steps to reproduce:
  1. `cargo check -p coderide_mcp_server_rust`
  2. Errore: `module 'common' is private`
- Risultato attuale: build failure.
- Risultato atteso: build success.
- Causa probabile: il modulo `trigram` e stato aggiunto recentemente e usa `ffi::common`, ma la visibilita non e stata aggiornata.
- Scope consentito: `RustCore/src/ffi/mod.rs`
- Non-scope: contenuto del modulo common, logica trigram
- Strategia di fix minimo: cambiare `mod common` in `pub(crate) mod common`
- Verifica post-fix: `cargo check` passa
- Commit previsto: `fix(rust-core): make ffi::common pub(crate) for trigram access`

## Fix applicato
- `RustCore/src/ffi/mod.rs`: `mod common` → `pub(crate) mod common`
