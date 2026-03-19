# 2026-03-19 - Review open PR execution context via Rust

## Modifiche
- aggiunto [open_pr_execution_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/open_pr_execution_context.rs) con la derivazione Rust di `baseBranchName`, `branchName` e `worktreePath` per `open_pr`
- estesi i DTO in [pr_result_models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/pr_result_models.rs) con request/response tipizzati per `ReviewPatchOpenPrExecutionContext`
- esposto il boundary [review_core_patch_build_open_pr_execution_context](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs) e registrato il modulo in [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/mod.rs)
- [ReviewPatchWorkflowService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift) usa ora il contesto Rust nello step `openPullRequest(...)`
- [ReviewPatchWorkflowService+DirectProvider.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+DirectProvider.swift) contiene il bridge fail-closed del nuovo boundary
- corretto il DTO Swift di `open_pr result` in [ReviewPatchWorkflowService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift) con `CodingKeys` esplicite per `prUrl`
- [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift) ora copre sia il nuovo execution context sia il vecchio result path

## Verifica eseguita
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::open_pr_execution_context::tests`
- `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testOpenPullRequestExecutionContextUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testOpenPullRequestExecutionContextFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testOpenPullRequestResultUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testOpenPullRequestResultFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testOpenPRContextUsesRustContextBuilder`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift,App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+DirectProvider.swift,Native/RustCore/src/review_patch/pr_result_models.rs,Native/RustCore/src/review_patch/open_pr_execution_context.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/ffi/review_patch.rs,Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift --format text`

## Esito
- anche il contesto esecutivo di `open_pr` non e' piu' source of truth Swift
- il boundary review strict resta senza nuove violazioni e con `Legacy hard-fail attivi: 0`
- il request/response contract di `open_pr result` e' riallineato su `prUrl`, evitando decode failures nascosti
