# P1 — Rust write_json senza file lock — race condition cross-process

## Bug Fix Record
- Categoria: B - Importante
- Bug: `write_json()` in `shared_review_state.rs` usa atomic write (temp + rename) ma non acquisisce un advisory file lock. Due processi (Swift app + Rust MCP server) possono scrivere contemporaneamente — il rename di uno sovrascrive il risultato dell'altro.
- Sintomo: saltuariamente, comandi o snapshot scritti dal Rust server vengono sovrascritti dalla Swift app (o viceversa), causando perdita di dati.
- Impatto: perdita silente di comandi review/bughunter, snapshot, patch records. Difficile da riprodurre ma impattante.
- Gravita: P1
- Steps to reproduce:
  1. Avviare BugHunter e CodeReview simultaneamente.
  2. Entrambi scrivono sullo stesso file JSON attraverso processi diversi.
  3. La write senza lock puo sovrascrivere l'altra.
- Risultato attuale: no file lock, race condition possibile.
- Risultato atteso: ogni write acquisisce un advisory lock esclusivo prima di scrivere.
- Causa probabile: `write_json` era stato scritto prima dell'introduzione del modulo `file_lock` nel crate.
- Scope consentito: `shared_review_state.rs`, funzione `write_json()`
- Non-scope: logica di business dei comandi, formato JSON, Swift side
- Moduli confinanti da verificare: `MCPSharedState+CrossProcessLock.swift` (lato Swift usa gia il lock)
- Strategia di fix minimo: wrappare il body di `write_json` con `with_file_lock(path, LockMode::Exclusive, || { ... })`
- Verifica post-fix: cargo check passa
- Commit previsto: `fix(rust-mcp): add advisory file lock to write_json`

## Fix applicato
- `shared_review_state.rs`: aggiunto `use crate::file_lock::{with_file_lock, LockMode}`
- `write_json()`: body wrappato con `with_file_lock(path, LockMode::Exclusive, || { ... })`
