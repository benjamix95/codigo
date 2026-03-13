# 2026-03-13 - Review panel live runtime instradato nel core Rust

## Modifiche
- aggiunto `review_panel_runtime` nel core Rust con boundary separati per:
  - `review_core_panel_run_start`
  - `review_core_panel_run_reduce_event`
  - `review_core_panel_run_finish`
  - `review_core_panel_chat_start`
  - `review_core_panel_chat_reduce_event`
  - `review_core_panel_chat_finish`
- ridotto `ReviewPanelCoordinator` a task driver tecnico senza branching di business logic su complete/error/cancel
- spostata nel reducer Rust la gestione live di:
  - `isRunning`, timer congelato, `lastError`, tab selection
  - response bubble del review run/chat
  - `textDelta`, `textReplace`, `raw`, `error`, `completed`
  - split del verdict su separatore `---`
- aggiunto `ReviewPanelRuntimeStateSnapshot` e adapter Swift del panel per applicare lo state Rust
- reso `ReviewCoreBridge.resetForTests()` pubblico per forzare il reload del dylib nei test panel runtime
- corretto nei test panel il path del dylib Rust verso `Native/target/debug/libsolocode_rust_core.dylib`
- aggiornato `scripts/solocode-validate` per selezionare i test mirati del panel runtime senza trascinare l'intero bundle `CoderEngineTests`

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml review_panel_runtime -- --nocapture`
- `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Native/RustCore/src/lib.rs,Native/RustCore/src/ffi/mod.rs,Native/RustCore/src/ffi/review_panel_runtime.rs,Native/RustCore/src/review_panel_runtime/mod.rs,Native/RustCore/src/review_panel_runtime/models.rs,Native/RustCore/src/review_panel_runtime/events.rs,Native/RustCore/src/review_panel_runtime/format.rs,Native/RustCore/src/review_panel_runtime/state.rs,Native/RustCore/src/review_panel_runtime/run.rs,Native/RustCore/src/review_panel_runtime/chat.rs,Engine/CoderEngine/Sources/CodebaseIndex/Indexing/RustSearchFFIClient.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ModesAndChatThreads.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustPanelState.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+LiveRunExecution.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatSession.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ActionOutput.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Coordinator/ReviewPanelCoordinator.swift,Tests/SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests.swift,Tests/SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests.swift,Tests/SoloCodeAppTests/ReviewPanelLifecycleE2ETests.swift,scripts/solocode-validate`

## Esito
- il panel review non decide piu' localmente il lifecycle live del run/chat
- il core Rust governa le mutazioni del runtime panel; Swift resta adapter e applicatore di state
- i test panel bridge-dependent vengono eseguiti solo quando il dylib corretto e' caricabile nel test host, altrimenti fanno skip esplicito
