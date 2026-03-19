# 2026-03-19 - Review patch canonical snapshot from Rust mutation

## Modifiche
- esteso [models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_command/models.rs) con `snapshot` opzionale in `ReviewCommandMutationResponse`
- [mutator.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_command/mutator.rs) costruisce ora uno snapshot canonico completo dopo la mutation, includendo `mutationSequence`, `lastUpdatedAt` e `outcome`
- [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_session/mod.rs) esporta il builder Rust di outcome necessario alla canonicalizzazione
- [ReviewCommandRustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewCommandRustBridge.swift) decodifica ora `snapshot` direttamente dal response Rust
- [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift) usa il `mutation.snapshot` canonico nei path `close_finding` e `upsert_patch`

## Verifica eseguita
- `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testUpsertPatchSnapshotMutationUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testCloseFindingExecutionClosesMergedFinding -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesRoutesThroughPatchExecutionRuntime -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesFailsClosedWhenPatchRuntimeIsUnavailable`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewCommandRustBridge.swift,App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift,Native/RustCore/src/review_command/models.rs,Native/RustCore/src/review_command/mutator.rs,Native/RustCore/src/review_session/mod.rs --format text`

## Esito
- i path patch-specifici non ricostruiscono piu' localmente lo snapshot finale dopo le mutation Rust
- lo snapshot canonico review e' piu' coerente tra Rust core e callsite Swift
- il boundary review strict resta senza nuove violazioni e con `Legacy hard-fail attivi: 0`
