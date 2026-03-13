# 2026-03-13 — Review Rust cutover tranche 1

## Modifiche
- aggiunti:
  - [review_panel.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_panel.rs)
  - [review_panel.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_panel.rs)
  - [test_support.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/test_support.rs)
  - [P1-2026-03-13-review-panel-structured-chat-extraction-was-still-owned-by-swift.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-13-review-panel-structured-chat-extraction-was-still-owned-by-swift.md)
  - [P1-2026-03-13-rustcore-plan-and-todo-tests-shared-home-were-flaky.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-13-rustcore-plan-and-todo-tests-shared-home-were-flaky.md)
  - [P1-2026-03-13-rust-search-build-script-copied-stale-target-artifacts.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-13-rust-search-build-script-copied-stale-target-artifacts.md)
- aggiornati:
  - [CodeReviewPanelStore+ChatFindings.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatFindings.swift)
  - [CodeReviewPanelStore+RustChatFindings.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustChatFindings.swift)
  - [CodeReviewPanelStore+RustLaunchPlanning.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustLaunchPlanning.swift)
  - [CodeReviewPanelStore+RustHistoryLiveState.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustHistoryLiveState.swift)
  - [CodeReviewPanelStore+RustHistoricalFindings.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustHistoricalFindings.swift)
  - [ReviewPatchRustBridge.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/ReviewPatchRustBridge.swift)
  - [review_patch.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs)
  - [plan_state.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/plan_state.rs)
  - [todo_state.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/todo_state.rs)
  - [lib.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/lib.rs)
  - [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/mod.rs)
  - [build_rust_search_backend.sh](/Users/benjaminstoica/SoloCode/scripts/build_rust_search_backend.sh)
  - [RUST_CUTOVER_BOUNDARY_BASELINE_2026-03-13.md](/Users/benjaminstoica/SoloCode/docs/migration/RUST_CUTOVER_BOUNDARY_BASELINE_2026-03-13.md)

## Cosa cambia
- il panel review non usa piu' parsing locale Swift per il blocco `review_findings`; la nuova API Rust `review_core_panel_chat_extract` estrae, normalizza e mergea i finding chat nel core nativo
- `review_core_panel_launch` sostituisce l'uso diretto del planner generico dal panel store e rende esplicito il boundary di launch
- `review_core_panel_history_live` e `review_core_panel_history_records` sostituiscono l'uso del reducer generico per i path history/live board
- `review_core_patch_workflow` introduce un entrypoint esplicito per il workflow patch, mantenendo compatibile il planner/runtime Rust esistente
- il test harness Rust usa ora un lock condiviso per i test che mutano `HOME`, eliminando la flakiness tra `plan_state` e `todo_state`
- `build_rust_search_backend.sh` copia ora la dylib dal target workspace corretto, evitando bundle/test run con artefatti Rust stale

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `./scripts/build_rust_search_backend.sh`
- `SOLOCODE_REVIEW_CORE_LIBRARY_PATH='/Users/benjaminstoica/SoloCode/Native/RustCore/build/lib/libsolocode_rust_core.dylib' xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests -only-testing:SoloCodeAppTests/ReviewPanelLifecycleE2ETests`

## Note
- il gate finale `zero Swift non-UI` sul dominio Code Review non e' ancora attivabile: questa tranche sposta ownership su entrypoint Rust dedicati, ma non drena ancora l'intero debito Swift in `Engine/CoderEngine/Sources/CodeReview` e `VerifiedFindingsCore`
- alcuni test app review restano `skipped` quando il runtime Rust non viene bootstrapato dentro l'ambiente Xcode del test runner; il run sopra non ha prodotto failure
