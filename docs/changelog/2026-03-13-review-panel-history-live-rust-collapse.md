# 2026-03-13 — Review panel history-live Rust collapse

## Modifiche
- assorbito `CodeReviewPanelStore+RustHistoryLiveState.swift` dentro [CodeReviewPanelStore+PipelineJobState.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PipelineJobState.swift)
- rimosso il file dal filesystem e dal `.pbxproj`
- corretto il boundary guard per distinguere:
  - report corrente del workspace, che ignora candidate file gia' cancellati
  - baseline `HEAD`, che puo' includere file mancanti tramite flag esplicito

## Comportamento
- nessun cambiamento funzionale del panel history-live
- ridotto di un ulteriore file il perimetro Swift non-UI del panel review
- il budget gate review contabilizza ora correttamente i diff che rimuovono file legacy

## Validazione eseguita
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`
- `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PipelineJobState.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustHistoryLiveState.swift,"Solo Code.xcodeproj/project.pbxproj",scripts/validate_rust_cutover_boundary.sh,Native/AppCoreProtocol/src/app_core.rs,Native/AppCoreRust/src/boundary/audit.rs,Native/AppCoreRust/src/bin/rust_cutover_guard.rs,Native/AppCoreRust/tests/app_core_boundary.rs`

## Note
- conteggio panel review aggiornato: `33 -> 32` file Swift legacy non-UI
- il prossimo target naturale e' il wrapper `RustPanelState` oppure un blocco store ancora Swift-owned con piu' logica di dominio
