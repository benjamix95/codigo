# P0 — uuid_like / generate_id producono ID non-univoci

## Bug Fix Record
- Categoria: A - Critico
- Bug: `uuid_like()` (review_tools.rs:772) e `generate_id()` (debug_tools.rs:1297) generano ID basati su timestamp con risoluzione millisecondi. Due chiamate nello stesso ms producono ID identici.
- Sintomo: Sessioni di review/security/bughunter possono ottenere lo stesso `session_id`/`run_id`. Log entry e hypothesis nel debug store possono collidere.
- Impatto: Sovrascrittura di sessioni, confusione tra dati di sessioni diverse, perdita dati silenziosa.
- Gravità: P0
- Steps to reproduce:
  1. Chiamare `review_start` due volte in rapida successione (< 1ms).
  2. Osservare che entrambe le sessioni ricevono lo stesso `session_id`.
  3. La seconda sessione sovrascrive i dati della prima.
- Risultato attuale:
  - `uuid_like()`: `format!("{:x}", state::reference_seconds_now().to_bits())` — basato su f64 timestamp bits.
  - `generate_id()`: `format!("{prefix}-{}", now_string())` — basato su timestamp millisecondi.
  - Nessun componente random o contatore atomico.
- Risultato atteso: ID globalmente univoci che non collidano mai, anche sotto chiamate concorrenti.
- Causa probabile: Implementazione placeholder durante la migrazione Rust. Manca una vera generazione UUID.
- Scope consentito:
  - `Native/CoderideMCPServerRust/src/review_tools.rs` — funzione `uuid_like()` (linea 772).
  - `Native/CoderideMCPServerRust/src/debug_tools.rs` — funzione `generate_id()` (linea 1297).
- Non-scope: logica di sessione, persistence, UI.
- Moduli confinanti da verificare: `review_start`, `security_start`, `bughunter_start`, `debug_session start`, `debug_log`, `debug_hypothesize propose`.
- Test da aggiungere o aggiornare:
  - Test: 1000 chiamate consecutive a `uuid_like()` → tutti ID distinti.
  - Test: 1000 chiamate consecutive a `generate_id()` → tutti ID distinti.
  - Test: due `review_start` in rapida successione → session_id diversi.
- Strategia di fix minimo: Usare il crate `uuid` (v4 random) per `uuid_like()`. Per `generate_id()`, aggiungere un contatore atomico (`AtomicU64`) al timestamp: `format!("{prefix}-{}-{}", now_string(), COUNTER.fetch_add(1, Ordering::Relaxed))`.
- Verifica post-fix:
  1. Unit test unicità su batch di 1000+ ID.
  2. `cargo test` sull'intero crate.
  3. Smoke test: due review_start in sequenza → session_id diversi.
- Commit previsto: `fix(mcp-rust): use uuid v4 for unique session/run/log IDs`
