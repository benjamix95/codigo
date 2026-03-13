# 2026-03-13 — Review history live Rust cutover

## Modifiche
- esteso il boundary Rust `review_core_panel_history_live` per consumare:
  - `snapshot`
  - `workerPlans`
  - `liveCards`
- aggiunto `Native/RustCore/src/review_history/live_inputs.rs` e spezzato il codice del live board da `mod.rs`
- assorbito `CodeReviewPanelStore+HistoryLive.swift` in [CodeReviewPanelStore+History.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+History.swift)
- rimosso il file dal filesystem e dal `.pbxproj`

## Comportamento
- il live board storico del panel review viene derivato dal core Rust anche quando `fileLedger` è vuoto
- Swift si limita a preparare payload compatti di worker plans e live cards
- conteggio panel review aggiornato: `28 -> 27`

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml review_history -- --nocapture`
- `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+History.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PipelineJobState.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+CompletionFinalization.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+HistoryLive.swift,Native/RustCore/src/review_history/mod.rs,Native/RustCore/src/review_history/live.rs,Native/RustCore/src/review_history/live_inputs.rs,Native/RustCore/src/review_panel.rs,Native/RustCore/src/ffi/review_panel.rs,Native/RustCore/src/ffi/review_core.rs,"Solo Code.xcodeproj/project.pbxproj",scripts/validate_rust_cutover_boundary.sh`

## Note
- questa tranche chiude uno dei pochi fallback store-heavy ancora Swift-owned nel panel review
- il prossimo target naturale resta `GitContext` o un blocco patch/workflow ancora davvero Swift-owned
