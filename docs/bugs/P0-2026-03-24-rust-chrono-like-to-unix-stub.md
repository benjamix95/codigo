# P0 — chrono_like_to_unix è uno stub che ritorna sempre 0.0

## Bug Fix Record
- Categoria: A - Critico
- Bug: `chrono_like_to_unix()` in `shared_review_state.rs` ritorna sempre `Some(0.0)` per qualsiasi stringa non vuota, rendendo tutti i timestamp delle snapshot errati.
- Sintomo: `started_at_reference_seconds` e `updated_at_reference_seconds` puntano a `-978307200.0` (data 2001-01-01 Apple epoch). Le comparazioni `max_by_key` su `lastUpdatedAt` non funzionano correttamente.
- Impatto: Selezione errata della snapshot attiva per review, security audit e bug hunter. Ordering dei risultati inaffidabile.
- Gravità: P0
- Steps to reproduce:
  1. Avviare due sessioni di review in sequenza.
  2. Osservare che `resolve_active_review_snapshot` non seleziona l'ultima sessione perché tutti i timestamp reference_seconds sono identici (tutti derivano da `chrono_like_to_unix` → 0.0).
- Risultato attuale: `chrono_like_to_unix` ritorna `Some(0.0)` per qualsiasi input non vuoto. Le funzioni `started_at_reference_seconds` e `updated_at_reference_seconds` producono lo stesso valore fisso per ogni snapshot.
- Risultato atteso: `chrono_like_to_unix` deve parsare correttamente stringhe ISO 8601 e ritornare il timestamp Unix reale. Le snapshot devono avere timestamp distinti e corretti.
- Causa probabile: La funzione è stata lasciata come stub durante la migrazione Rust. Il commento e il body indicano un placeholder mai completato.
- Scope consentito: `Native/CoderideMCPServerRust/src/shared_review_state.rs` — funzione `chrono_like_to_unix` (linee 242-248).
- Non-scope: logica di selezione snapshot, UI timestamp display, persistence store.
- Moduli confinanti da verificare: `resolve_active_review_snapshot`, `resolve_active_bughunter_snapshot`, `make_review_snapshot_record` (tutti in `review_tools.rs`).
- Test da aggiungere o aggiornare:
  - Unit test: `chrono_like_to_unix` con input ISO 8601 valido → timestamp Unix corretto.
  - Unit test: `chrono_like_to_unix` con stringa vuota → `None`.
  - Unit test: `chrono_like_to_unix` con formato non standard → gestione graceful.
  - Regression test: due snapshot con date diverse → ordering corretto.
- Strategia di fix minimo: Implementare il parsing ISO 8601 reale in `chrono_like_to_unix` usando il crate `chrono` (già in dipendenza o aggiungendolo). Formati da supportare: `2026-03-24T10:30:00Z`, `2026-03-24T10:30:00+01:00`, `2026-03-24 10:30:00`.
- Verifica post-fix:
  1. Unit test della funzione con diversi formati di data.
  2. Test che `resolve_active_review_snapshot` selezioni correttamente la snapshot più recente.
  3. `cargo test` sull'intero crate.
- Commit previsto: `fix(mcp-rust): implement real ISO 8601 parsing in chrono_like_to_unix`
