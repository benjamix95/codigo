# 2026-03-13 — Rust cutover boundary guard e fondazione AppCore

## Modifiche
- aggiunto `Native/AppCoreRust` come nuovo crate Rust foundation per il cutover applicativo
- esteso `Native/AppCoreProtocol` con i DTO versionati per `AppCoreRequest/AppCoreResponse` e il boundary audit Swift/Rust
- implementato il binario Rust `rust_cutover_guard` per auditare il boundary Swift del repository
- aggiunta l'allowlist `Config/validation/rust-cutover-swift-allowlist.txt` per i soli path UI, binding minimi e bootstrap Apple
- integrato il guardrail nello script `scripts/solocode-validate` tramite il wrapper `scripts/validate_rust_cutover_boundary.sh`
- corretto il selettore della validation per non lanciare l'intero bundle `CoderEngineTests` quando il diff tocca solo `Native/` e file infrastrutturali del guardrail
- aggiornato il workflow CI `.github/workflows/validation.yml` per usare `fetch-depth: 2` e rendere disponibile il diff del commit
- aggiornato `.gitignore` per escludere artefatti `Native/**/target/` e `tmp/`
- documentato il gap strutturale in `docs/bugs/P1-2026-03-13-rust-cutover-boundary-guard-missing.md`

## Comportamento
- la pipeline blocca l'introduzione di **nuovi** file Swift non-UI non allowlisted
- i file Swift legacy non-UI gia' presenti vengono censiti come backlog di dominio, ma non bloccano ancora il commit di tranche di migrazione
- il boundary audit e' incapsulato in Rust e riusabile come base del futuro `AppCoreBridge`

## Validazione eseguita
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`
- `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Native/Cargo.toml,Native/AppCoreProtocol/src/lib.rs,Native/AppCoreProtocol/src/app_core.rs,Native/AppCoreRust/Cargo.toml,Native/AppCoreRust/src/lib.rs,Native/AppCoreRust/src/app_core.rs,Native/AppCoreRust/src/boundary/mod.rs,Native/AppCoreRust/src/boundary/allowlist.rs,Native/AppCoreRust/src/boundary/classify.rs,Native/AppCoreRust/src/boundary/audit.rs,Native/AppCoreRust/src/bin/rust_cutover_guard.rs,Native/AppCoreRust/tests/app_core_boundary.rs,Config/validation/rust-cutover-swift-allowlist.txt,scripts/validate_rust_cutover_boundary.sh,scripts/solocode-validate,.github/workflows/validation.yml,.gitignore`

## Note
- questa tranche e' intenzionalmente piccola e confinata: non sposta ancora runtime UI-adjacent dal panel review, ma mette un guardrail verificabile che impedisce ulteriore espansione del debito Swift non-UI.
