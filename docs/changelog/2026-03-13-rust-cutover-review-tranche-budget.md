# 2026-03-13 — Budget di tranche per il cutover Rust review

## Modifiche
- esteso `BoundaryAuditRequest` con `legacy_non_ui_budget_by_prefix`
- aggiunti nel report i conteggi `budget_exceeded_legacy_non_ui_files` e `budget_exceeded_prefix_counts`
- il guard `rust_cutover_guard` ora fallisce per:
  - nuovi file Swift non-UI
  - legacy Swift non-UI oltre il budget consentito per il prefisso toccato
- la shell `validate_rust_cutover_boundary.sh` calcola la baseline review da `HEAD` e impone `budget = baseline - 1`

## Comportamento
- fuori dal dominio review non cambia nulla: restano bloccati solo i nuovi file Swift non-UI
- se il diff tocca review, il commit passa solo se riduce il backlog Swift non-UI del prefisso coinvolto
- se il backlog review resta invariato o cresce, il gate fallisce con i conteggi `budget_exceeded_prefix_counts`

## Validazione eseguita
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`
- `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Native/AppCoreProtocol/src/app_core.rs,Native/AppCoreRust/src/boundary/audit.rs,Native/AppCoreRust/src/bin/rust_cutover_guard.rs,Native/AppCoreRust/tests/app_core_boundary.rs,scripts/validate_rust_cutover_boundary.sh`
- `scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore.swift --format text`

## Note
- questo non chiude il cutover review
- sblocca pero' il percorso corretto: da adesso ogni tranche review deve ridurre davvero il debito legacy rispetto alla baseline precedente
