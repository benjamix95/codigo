# 2026-03-19 — Review patch prepare context in Rust

## Modifiche
- aggiunto in Rust `review_patch::prepare_context` con builder del contesto minimo di `prepare_patch`
- esposto il nuovo endpoint FFI `review_core_patch_build_prepare_context`
- spostati in Rust:
  - branch naming del prepare patch
  - prompt orchestration del patch preview
- aggiornati entrambi i path Swift di `preparePatch(...)` per usare il contesto derivato da Rust
- aggiunti test Rust sul builder del prepare context
- aggiornati i test Swift:
  - prompt Rust-gated
  - fail-closed su `prepare_patch` e `verify_patch` nel command path
  - conferma dei path di finalizzazione deferred e provider selection

## Motivazione
- ridurre un altro pezzo di semantica patch rimasta in Swift e convergere `prepare_patch` verso il review core Rust

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests`
