# P1 - L'hard-fail review a zero immediato bloccava il drenaggio incrementale verso Rust

## Bug Fix Record
- Categoria: A
- Bug: il gate review introdotto come `zero legacy immediato` rendeva impossibile migrare il dominio review in tranche piccole e verificabili.
- Sintomo: qualunque diff che toccasse un prefisso review falliva anche se la modifica riduceva davvero il debito Swift non-UI; il criterio era "zero subito", non "deve scendere rispetto a HEAD".
- Impatto: il piano "Code Review prima" restava formalmente corretto ma operativamente impraticabile; nessuna tranche intermedia avrebbe potuto essere validata.
- Gravità: P1
- Steps to reproduce:
  1. Toccare un file sotto `App/SoloCodeApp/Sources/Panels/CodeReview`.
  2. Eseguire `scripts/validate_rust_cutover_boundary.sh`.
  3. Osservare che il gate fallisce finché esiste backlog legacy, anche se l'intenzione della tranche è drenarlo gradualmente.
- Risultato attuale: il dominio review era bloccato da una semantica "zero legacy subito" incompatibile con il workflow incrementale imposto dal repository.
- Risultato atteso: quando un diff tocca review, la validation deve imporre una riduzione misurabile del backlog legacy rispetto a `HEAD`, e continuare a fallire se il conteggio resta uguale o aumenta.
- Causa probabile: il gate della tranche precedente aveva reso il target finale immediatamente bloccante, senza modellare una traiettoria di riduzione commit-by-commit.
- Scope consentito:
  - `Native/AppCoreProtocol`
  - `Native/AppCoreRust`
  - `scripts/validate_rust_cutover_boundary.sh`
- Non-scope:
  - migrazione dei moduli review stessi
  - cambi UI
  - modifica dell'allowlist
- Moduli confinanti da verificare:
  - `rust_cutover_guard`
  - calcolo baseline da `HEAD`
  - output JSON del boundary audit
- Test da aggiungere o aggiornare:
  - regressione Rust per budget per-prefisso
  - validazione shell del caso review senza riduzione backlog
- Strategia di fix minimo:
  - introdurre budget legacy per prefisso nel boundary audit
  - calcolare il budget dalla baseline `HEAD - 1`
  - mantenere il fail-fast quando il diff non riduce il conteggio legacy
- Verifica post-fix:
  - `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`
  - `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Native/AppCoreProtocol/src/app_core.rs,Native/AppCoreRust/src/boundary/audit.rs,Native/AppCoreRust/src/bin/rust_cutover_guard.rs,Native/AppCoreRust/tests/app_core_boundary.rs,scripts/validate_rust_cutover_boundary.sh`
  - `scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore.swift --format text`
- Commit previsto: `fix(cutover): require review debt to decrease per tranche`

## Fix applicato
- aggiunto budget per-prefisso al boundary audit Rust
- il guard fallisce solo sulla porzione legacy che eccede il budget della tranche
- la shell di validation calcola il budget dai file Swift presenti in `HEAD` e richiede una riduzione di almeno 1 per ogni prefisso review toccato

## Residuo
- il dominio review resta ancora Swift-heavy
- il nuovo gate lo rende finalmente migrabile in piu' tranche senza abbassare il target finale a zero
