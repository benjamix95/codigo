# 2026-03-19 - Review patch prepare draft result via Rust

## Modifiche
- aggiunto [prepare_result.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/prepare_result.rs) con il reducer Rust del draft artifact `prepare_patch`
- estesi i DTO in [models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/models.rs) con request/response tipizzati per `ReviewPatchPrepareResult`
- esposto il boundary [review_core_patch_build_prepare_result](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs) e registrato il modulo in [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/mod.rs)
- [ReviewPatchWorkflowService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift) e [ReviewPatchWorkflowService+DirectProvider.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+DirectProvider.swift) usano ora un unico bridge Rust per costruire il draft artifact della patch
- [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift) include regressioni dedicate per il nuovo bridge `prepare result`

## Verifica eseguita
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::prepare_result::tests`
- `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPreparePatchPromptIncludesVerificationRemediationAndInvariantContext -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPreparePatchContextFailsClosedWhenRustPrepareContextUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareDraftArtifactUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareDraftArtifactFailsClosedWhenRustPrepareResultUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesRoutesThroughPatchExecutionRuntime -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesFailsClosedWhenPatchRuntimeIsUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testOpenPRContextUsesRustContextBuilder`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift,App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+DirectProvider.swift,Native/RustCore/src/review_patch/models.rs,Native/RustCore/src/review_patch/prepare_result.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/ffi/review_patch.rs,Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift --format text`

## Esito
- il patch workflow non mantiene piu' in Swift la derivazione duplicata del draft artifact
- il boundary review strict resta senza nuove violazioni e con `Legacy hard-fail attivi: 0`
- Swift resta owner solo di git/provider I/O e validation, non della semantica del prepare result
