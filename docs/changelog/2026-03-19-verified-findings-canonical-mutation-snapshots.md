# 2026-03-19 - Verified findings canonical mutation snapshots

## Modifiche
- [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift) non ricostruisce più localmente lo snapshot nei path `close_finding` e `upsert_patch`.
- Entrambi i path accettano ora solo `mutation.snapshot` come risposta canonica del mutator Rust.

## Verifica eseguita
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testUpsertPatchSnapshotMutationUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testUpsertPatchSnapshotMutationFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testCloseFindingExecutionClosesMergedFinding -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testCloseFindingFailsWhenRustPatchRuntimeIsDisabled -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testCloseFindingFailsWhenPatchRuntimeResultBridgeIsUnavailable`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift --format text`

## Esito
- verified findings patch execution non mantiene più una riduzione locale dello snapshot
- i path `close_finding` e `upsert_patch` restano coerenti con l'obiettivo Rust fail-closed
