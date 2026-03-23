# 2026-03-19 - Review open PR context via Rust

## Modifiche
- aggiunto [open_pr_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/open_pr_context.rs) con la derivazione Rust di `title/body` per lo step `open_pr`
- estesi i model FFI in [pr_result_models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/pr_result_models.rs) con request/response tipizzati per `ReviewPatchOpenPrContext`
- esposto il boundary [review_core_patch_build_open_pr_context](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs) e registrato il modulo in [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/mod.rs)
- [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift) ora chiama solo il core Rust per ottenere il contesto `open_pr`
- [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift) include una regressione dedicata sul boundary Rust e usa un resolver dylib stabile basato su `#filePath`
- lo stesso file di test ora carica esplicitamente il runtime Rust anche nel failure path `prepareVerifiedPatches`, perche' il reducer `mark_patch_prepare_failed` e' Rust-owned

## Verifica eseguita
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::open_pr_context::tests`
- `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testAutoPrepareEligibleFindingIdsOnlyReturnsVerifiedFilteredOriginsWithoutExistingPatch -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testAutoPrepareEligibleFindingIdsFailsClosedWhenRustRuntimeIsDisabled -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesRoutesThroughPatchExecutionRuntime -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesFailsClosedWhenPatchRuntimeIsUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testOpenPRContextUsesRustContextBuilder`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift,Native/RustCore/src/ffi/review_patch.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/review_patch/pr_result_models.rs,Native/RustCore/src/review_patch/open_pr_context.rs,Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift --format text`

## Esito
- anche il contesto `open_pr` del patch workflow non e' piu' source of truth Swift
- la regressione app-side esercita davvero il boundary Rust senza `skip` ambientali
- il gate review strict resta senza nuove violazioni e con `Legacy hard-fail attivi: 0`
