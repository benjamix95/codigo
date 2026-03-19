# 2026-03-19 - Review apply-fix persisted mutation via Rust

## Modifiche
- [ReviewPatchWorkflowService+ApplyLifecycle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift) instrada ora il path persisted `markFindingFixApplied(...)` al mutator Rust `apply_fix`.
- [CodigoAppCodeReviewCommandLoopTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests.swift) copre sia il caso positivo sia il fail-closed quando il runtime Rust è disabilitato.

## Verifica eseguita
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testMarkFindingFixAppliedUsesRustMutationForPersistedSnapshot -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testMarkFindingFixAppliedFailsClosedWhenRustMutationRuntimeIsDisabled`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift --format text`

## Esito
- il path persisted `apply_fix` non mantiene più una mutazione locale Swift
- il comportamento fail-closed resta preservato
