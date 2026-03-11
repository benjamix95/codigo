# P3 — Warning residui nel crate Rust del review core dopo le ultime tranche

## Bug Fix Record
- Categoria: C
- Bug: il crate Rust compilava correttamente ma lasciava warning per import e helper non usati nei moduli `review_mcp`, `review_pipeline` e `review_value`.
- Sintomo: `cargo test` e `scripts/build_rust_search_backend.sh` producevano warning ripetuti su import morti e campi compat-only.
- Impatto: nessun blocco funzionale, ma segnale di rumore nel build e minore confidenza nel delta reale dei warning.
- Gravita': bassa.
- Steps to reproduce:
  1. Eseguire `cargo test --manifest-path Native/RustCore/Cargo.toml`.
  2. Osservare warning su `unused import`, helper morti e campi payload non letti.
- Risultato attuale: il crate deve compilare senza warning locali inutili.
- Risultato atteso: build/test Rust puliti, con eccezioni marcate esplicitamente solo se intenzionali.
- Causa probabile: refactor incrementale delle ultime tranche review/MCP.
- Scope consentito:
  - `Native/RustCore/src/review_mcp/*`
  - `Native/RustCore/src/review_pipeline/*`
  - `Native/RustCore/src/review_value.rs`
- Non-scope:
  - logica applicativa Swift
  - UI
- Moduli confinanti da verificare:
  - build crate Rust
- Test da aggiungere o aggiornare:
  - nessuno; basta rerun del crate tests
- Strategia di fix minimo:
  - rimuovere import/helper morti
  - annotare i campi payload volutamente non letti
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
- Commit previsto: `chore(review): clean rust review-core warnings`
