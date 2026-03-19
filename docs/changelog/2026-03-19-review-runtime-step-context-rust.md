# 2026-03-19 - Review runtime step context via Rust

## Modifiche
- aggiunto [step_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/step_context.rs) con il reducer Rust del contesto step-by-step del patch runtime
- esposto il boundary [review_core_patch_build_step_context](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs) e registrato il modulo in [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/mod.rs)
- [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift) usa ora un `runtimeStepContext(...)` Rust per validare `patch`, `finding` e `providerRegistry`
- il loop runtime continua a eseguire l'I/O concreto dei passi, ma non decide piu' localmente le precondizioni di dominio

## Verifica eseguita
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::step_context::tests`
- `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testCloseFindingExecutionClosesMergedFinding -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testCloseFindingFailsWhenRustPatchRuntimeIsDisabled -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testCloseFindingFailsWhenPatchRuntimeResultBridgeIsUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesRoutesThroughPatchExecutionRuntime -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesFailsClosedWhenPatchRuntimeIsUnavailable`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift,Native/RustCore/src/review_patch/step_context.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/ffi/review_patch.rs,Native/RustCore/src/review_patch/models.rs --format text`

## Esito
- il loop runtime patch non mantiene piu' in Swift la validazione step-specifica delle sue dipendenze
- il boundary review strict resta senza nuove violazioni e con `Legacy hard-fail attivi: 0`
