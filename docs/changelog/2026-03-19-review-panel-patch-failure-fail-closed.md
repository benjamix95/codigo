# 2026-03-19 - Review panel patch failure fail-closed

## Modifiche
- [CodeReviewPanelStore+PatchWorkflow+Execution.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+PatchWorkflow+Execution.swift) non ricostruisce più localmente lo snapshot nel path `markPatchFailure(...)`.
- [CodeReviewPanelSessionScopingTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CodeReviewPanelSessionScopingTests.swift) copre ora il fail-closed quando il reducer Rust di patch failure è indisponibile.
- Lo smoke test positivo attende esplicitamente il flush di `scheduleCodeReviewSnapshotIngest(...)`, così non dipende più da timing impliciti.

## Verifica eseguita
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelApplyFixFailsClosedWithoutWorkspaceAndDoesNotTouchOtherFindings -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelApplyFixDoesNotMutateSnapshotWhenRustFailureReducerIsUnavailable`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+PatchWorkflow+Execution.swift --format text`

## Esito
- il panel review non mantiene più un fallback locale sul patch failure path
- il comportamento fail-closed è coerente con il cutover Rust
