# 2026-03-19 — Review patch runtime fail-closed

## Modifiche
- esteso il runtime patch Rust con stato canonico minimo:
  - `action`
  - `sessionId`
  - `findingId`
  - `conversationId`
  - `steps`
  - `completedSteps`
  - `lastTransitionAt`
  - `terminalReason`
- reso `VerifiedFindingsPatchExecutionService` fail-closed quando:
  - `review_core_patch_start_runtime` non è disponibile
  - `review_core_patch_apply_runtime_result` non risponde
  - il runtime patch ritorna uno stato errore/failure durante l’avanzamento
- rimosso il fallback Swift locale per `close_finding`
- aggiunti hook di test per simulare runtime patch start/advance nei test app-side
- aggiunte regressioni su service patch e command-loop close finding

## Motivazione
- chiudere il fail-open più evidente del patch lifecycle prima di spostare in Rust l’esecuzione completa dei passi patch

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopCloseFindingTests`
