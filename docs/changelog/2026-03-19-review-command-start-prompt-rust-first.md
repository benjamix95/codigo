# 2026-03-19 - Review command start prompt Rust-first

## Modifiche
- introdotto un nuovo boundary Rust `review_core_command_build_start_prompt`
- aggiunto il modulo Rust `Native/RustCore/src/review_command/prompts.rs`
- il command `review_start` usa ora il review core Rust anche per la costruzione del prompt
- rimosso il costruttore locale `reviewPrompt(...)` dal `CodigoApp`
- aggiornati i test del command loop:
  - i casi `start/configure/dismiss/comment` che richiedono il review core lo dichiarano esplicitamente
  - aggiunto il caso di failure esplicita quando il runtime Rust è disabilitato sul `start`

## Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testStartCommandRemainsProcessingUntilDeferredReviewCompletes -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testStartCommandFailsWhenRustRuntimeIsDisabled -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testDeferredReviewMarksCommandFailedWhenSessionFails -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testConfigureCommandUpdatesLiveSessionThroughCommandLoop -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testConfigureCommandUpdatesPersistedSnapshotThroughRustMutation -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testConfigureCommandFailsWhenRustMutationRuntimeIsDisabled -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testDismissCommandUsesRustPlannerAndPersistsWontFix -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testCommentCommandUsesRustMutationAndAppendsComment`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSharedCodeReviewCommandsTests`

## Esito
- il command loop review è ora Rust-first su:
  - planner
  - mutazioni immediate (`configure`, `dismiss`, `comment`)
  - prompt del `start`
- Swift mantiene ancora il bridge di esecuzione deferred (`provider.send`, session state bridge, heartbeat/final mark), ma non porta più una seconda semantica del command bus review
- con questo batch considero completata la tranche 3; i prossimi blocchi sono patch workflow, MCP ownership e residui engine-side
