# 2026-03-19 - Review revalidate and rollback context via Rust

## Modifiche
- aggiunti [revalidate_execution_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/revalidate_execution_context.rs) e [rollback_execution_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/rollback_execution_context.rs)
- estesi i DTO in [models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/models.rs) con request/response tipizzati per i nuovi execution context
- esposti i boundary [review_core_patch_build_revalidate_execution_context](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs) e [review_core_patch_build_rollback_execution_context](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs)
- [ReviewPatchWorkflowService+ApplyLifecycle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift) usa ora helper fail-closed per `revalidatePatch(...)` e `rollbackPatch(...)`
- [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift) copre i nuovi bridge oltre ai result reducer esistenti

## Verifica eseguita
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::revalidate_execution_context::tests`
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::rollback_execution_context::tests`
- `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRevalidatePatchExecutionContextUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRevalidatePatchExecutionContextFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRevalidatePatchResultUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRevalidatePatchResultFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRollbackPatchExecutionContextUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRollbackPatchExecutionContextFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRollbackPatchResultUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRollbackPatchResultFailsClosedWhenRustRuntimeUnavailable`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift,Native/RustCore/src/review_patch/models.rs,Native/RustCore/src/review_patch/revalidate_execution_context.rs,Native/RustCore/src/review_patch/rollback_execution_context.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/ffi/review_patch.rs,Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift --format text`

## Esito
- il lifecycle `revalidate/rollback` non mantiene piu' in Swift le precondizioni di dominio
- il prefix del rollback temp file e' ora derivato dal core Rust
- il boundary review strict resta senza nuove violazioni e con `Legacy hard-fail attivi: 0`
