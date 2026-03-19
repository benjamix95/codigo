# 2026-03-19 - Review resolve conflicts context via Rust

## Modifiche
- aggiunto [resolve_conflicts_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/resolve_conflicts_context.rs) con la derivazione Rust del contesto `resolve_conflicts`
- estesi i DTO in [pr_result_models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/pr_result_models.rs) con request/response tipizzati per `ReviewPatchResolveConflictsContext`
- esposto il boundary [review_core_patch_build_resolve_conflicts_context](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs) e registrato il modulo in [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/mod.rs)
- [ReviewPatchWorkflowService+Merge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+Merge.swift) usa ora un helper fail-closed per ottenere da Rust `worktreePath`, `branchName`, `baseBranchName` e `commitMessage`
- [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift) copre il nuovo bridge `resolve_conflicts context` e il vecchio `resolveConflictsResult`

## Verifica eseguita
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::resolve_conflicts_context::tests`
- `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testResolveConflictsExecutionContextUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testResolveConflictsExecutionContextFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testResolveConflictsResultUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testResolveConflictsResultFailsClosedWhenRustRuntimeUnavailable`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+Merge.swift,Native/RustCore/src/review_patch/pr_result_models.rs,Native/RustCore/src/review_patch/resolve_conflicts_context.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/ffi/review_patch.rs,Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift --format text`

## Esito
- il passo `resolve_conflicts` non mantiene piu' in Swift la validazione del merge context
- il commit message di sync e' ora canonicale in Rust
- il boundary review strict resta senza nuove violazioni e con `Legacy hard-fail attivi: 0`
