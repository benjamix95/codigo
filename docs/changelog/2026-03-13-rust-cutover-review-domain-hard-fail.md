# 2026-03-13 — Hard-fail del dominio review nel Rust cutover guard

## Modifiche
- esteso `BoundaryAuditRequest` con `enforce_legacy_zero_prefixes`
- estesi summary/response del guard con i conteggi dedicati ai prefissi hard-fail
- aggiornato `audit_request(...)` per:
  - aggiungere ai candidate file l'intero contenuto Swift dei prefissi enforced
  - contare separatamente il backlog legacy che rientra nei prefissi hard-fail
- aggiornato `rust_cutover_guard` per uscire con errore anche quando esistono legacy Swift non-UI dentro prefissi enforced
- aggiornato `scripts/validate_rust_cutover_boundary.sh` per attivare automaticamente l'enforcement sui prefissi review quando il diff li tocca
- aggiunta regressione Rust che prova il caso "candidate list parziale + prefisso review enforced"

## Comportamento
- fuori dal dominio review, il guard continua a bloccare solo i nuovi file Swift non-UI
- quando una modifica entra nel perimetro review, la validation promuove quel dominio a tranche hard-fail
- il diff non puo' piu' avanzare nel dominio review fingendo che il backlog legacy sia solo inventario informativo

## Validazione eseguita
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`
- `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Native/AppCoreProtocol/src/app_core.rs,Native/AppCoreRust/src/boundary/audit.rs,Native/AppCoreRust/src/bin/rust_cutover_guard.rs,Native/AppCoreRust/tests/app_core_boundary.rs,scripts/validate_rust_cutover_boundary.sh,docs/bugs/P1-2026-03-13-review-cutover-domain-not-hard-failed.md,docs/changelog/2026-03-13-rust-cutover-review-domain-hard-fail.md,docs/migration/RUST_CUTOVER_BOUNDARY_BASELINE_2026-03-13.md`

## Note
- questa tranche non migra ancora il runtime review a Rust
- introduce pero' il primo gate duro coerente con il piano "Code Review prima"
