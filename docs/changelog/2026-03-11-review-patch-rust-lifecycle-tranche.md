# 2026-03-11 — Review patch lifecycle e command validation spostati nel core Rust

## Modifiche
- aggiunto il nuovo dominio Rust `review_patch` con:
  - `models`
  - `planner`
  - entrypoint `review_core_patch_handle_action`
- introdotto `ReviewPatchRustBridge` nel core Swift
- `VerifiedFindingsLifecycleCommandService` usa ora il validator Rust per queue context e preconditions patch
- `VerifiedFindingsPatchExecutionService` usa ora il planner Rust per decidere la sequenza degli step patch, lasciando a Swift solo l’esecuzione concreta dei side effects
- `SecurityWorkflowService` e `BugHunterWorkflowService` beneficiano del nuovo path attraverso il lifecycle service condiviso
- aggiornato `Solo Code.xcodeproj` per includere il nuovo bridge patch

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/BugHunterWorkflowServiceTests -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests`

## Esito
- queue context e preconditions lifecycle non sono più decisi solo da Swift
- il sequencing di `apply_fix/apply_patch` e delle altre patch actions passa da un planner Rust
- l’esecuzione concreta di Git/provider/PR resta intenzionalmente Swift come adapter runtime
