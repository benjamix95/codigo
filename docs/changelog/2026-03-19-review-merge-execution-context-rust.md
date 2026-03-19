# 2026-03-19 - Review merge execution context via Rust

## Modifiche
- aggiunto [merge_execution_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/merge_execution_context.rs) con la derivazione Rust del contesto `merge_pr`
- estesi i DTO in [pr_result_models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/pr_result_models.rs) con request/response tipizzati per `ReviewPatchMergeExecutionContext`
- esposto il boundary [review_core_patch_build_merge_execution_context](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs) e registrato il modulo in [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/mod.rs)
- [ReviewPatchWorkflowService+Merge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+Merge.swift) usa ora un helper fail-closed per ottenere da Rust `prURL`, `firstMergeAuto`, `retryAfterConflicts` e `retryMergeAuto`
- nello stesso file i DTO merge sono allineati su `prUrl` con `CodingKeys` esplicite
- [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift) copre il nuovo bridge `merge execution context` e il vecchio `mergePullRequestResult`

## Verifica eseguita
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::merge_execution_context::tests`
- `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testMergePullRequestExecutionContextUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testMergePullRequestExecutionContextFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testMergePullRequestResultUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testMergePullRequestResultFailsClosedWhenRustRuntimeUnavailable`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+Merge.swift,Native/RustCore/src/review_patch/pr_result_models.rs,Native/RustCore/src/review_patch/merge_execution_context.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/ffi/review_patch.rs,Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift --format text`

## Esito
- il passo `merge_pr` non mantiene piu' in Swift la decisione semantica `safeOnly -> retry`
- il contract `prUrl` e' allineato sul path merge
- il boundary review strict resta senza nuove violazioni e con `Legacy hard-fail attivi: 0`
