# 2026-03-16 - Rust cutover strict audit mode

## Cosa ho fatto
- aggiunto al binario `rust_cutover_guard` il flag `--fail-on-legacy-non-ui`
- estratta la logica di exit code in una funzione dedicata con unit test
- documentato il baseline corrente del workspace e del dominio `CodeReview` in `docs/migration/RUST_CUTOVER_AUDIT_2026-03-16.md`
- registrato il gap architetturale come bug P1 in `docs/bugs/P1-2026-03-16-rust-cutover-zero-legacy-audit-still-failing.md`

## Perche'
- finora il guard Rust bloccava nuovi file Swift non-UI e i tranche gate review, ma non offriva un comando strict semplice per rispondere se il repository fosse davvero a zero legacy non-UI
- la richiesta corrente richiedeva una risposta verificabile sullo stato del panel review e del progetto nel suo complesso

## Risultato osservato
- workspace completo:
  - exit code `2`
  - `1497` file Swift legacy non-UI
- dominio review:
  - exit code `2`
  - `72` file Swift legacy non-UI

## Verifica eseguita
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`
- `cargo run --quiet --manifest-path Native/AppCoreRust/Cargo.toml --bin rust_cutover_guard -- --workspace /Users/benjaminstoica/SoloCode --allowlist Config/validation/rust-cutover-swift-allowlist.txt --fail-on-legacy-non-ui --format text`
- audit review-scope documentato nel report di migrazione del 2026-03-16

## Note
- questa modifica non completa il cutover Rust
- questa modifica rende il cutover misurabile in modalita' strict, cosi' le tranche successive possono essere validate contro un target esplicito
