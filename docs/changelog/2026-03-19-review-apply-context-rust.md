# 2026-03-19 - Review apply execution context via Rust

## Modifiche
- aggiunto [apply_execution_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/apply_execution_context.rs)
- estesi i DTO in [models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/models.rs) con request/response tipizzati per `ReviewPatchApplyExecutionContext`
- esposto il boundary [review_core_patch_build_apply_execution_context](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs) e registrato il modulo in [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/mod.rs)
- [ReviewPatchWorkflowService+ApplyLifecycle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift) usa ora il bridge Rust per il context di `applyPatch(...)`
- nello stesso file il path reale `applyPatch(...)` continua a restituire `patchNotVerified` quando la patch non e' verificata, ma il check e' ormai Rust-owned
- [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift) copre il nuovo bridge `apply execution context` e il contratto storico del path reale

## Verifica eseguita
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::apply_execution_context::tests`
- `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testApplyPatchExecutionContextUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testApplyPatchExecutionContextFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testApplyPatchRejectsArtifactThatWasNotVerified -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testApplyPatchResultUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testApplyPatchResultFailsClosedWhenRustRuntimeUnavailable`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift,Native/RustCore/src/review_patch/models.rs,Native/RustCore/src/review_patch/apply_execution_context.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/ffi/review_patch.rs,Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift --format text`

## Esito
- il passo `apply_patch` non mantiene piu' in Swift il proprio execution context
- il boundary review strict resta senza nuove violazioni e con `Legacy hard-fail attivi: 0`
