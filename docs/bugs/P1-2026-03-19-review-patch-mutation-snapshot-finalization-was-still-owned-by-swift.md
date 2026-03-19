# P1 - La finalizzazione dello snapshot dopo mutation patch era ancora owned da Swift

## Bug Fix Record
- Categoria: B
- Bug: [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift) e [ReviewCommandRustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewCommandRustBridge.swift) ricostruivano ancora localmente il `CodeReviewSessionSnapshot` dopo `close_finding`, `upsert_patch` e `configure`.
- Sintomo:
  - `snapshot.copying(...)`
  - `buildOutcomeSummary()`
  - aggiornamento locale di `lastUpdatedAt`
  dopo una mutation che il core Rust aveva gia' calcolato semanticamente.
- Impatto: il dominio review manteneva ancora semantica Swift sul path patch-specifico della finalizzazione snapshot, con duplicazione del reducer Rust.
- Gravita': alta, perche' tocca outcome summary, mutation sequencing e stato canonico post-mutation.
- Steps to reproduce:
  1. Aprire [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift).
  2. Cercare `closeFindingWithRustMutation(...)` e `upsertPatchWithRustMutation(...)`.
  3. Verificare che, dopo il bridge Rust, lo snapshot venga ancora ricostruito in Swift.
- Risultato attuale: il mutator Rust non restituisce ancora uno snapshot canonico completo e Swift colma il vuoto.
- Risultato atteso: il bridge di mutation deve restituire uno snapshot finale gia' canonicalizzato, incluso `mutationSequence`, `outcome` e `lastUpdatedAt`.
- Causa probabile: il mutator Rust era nato per restituire solo slices (`findings`, `patches`, `events`) e non lo snapshot finale completo.
- Scope consentito:
  - [ReviewCommandRustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewCommandRustBridge.swift)
  - [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift)
  - [models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_command/models.rs)
  - [mutator.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_command/mutator.rs)
  - [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_session/mod.rs)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - panel runtime
  - provider execution
  - patch result reducers gia' migrati
- Moduli confinanti da verificare:
  - `ReviewPatchWorkflowServiceTests`
  - `ReviewPatchRuntimeFinalizationService`
  - `configuredReviewSnapshot(...)`
- Test da aggiungere o aggiornare:
  - smoke sui path `upsertPatchSnapshot` e `close_finding`
  - smoke sul failure path `prepareVerifiedPatches`
- Strategia di fix minimo:
  - far restituire al mutator Rust uno `snapshot` canonico opzionale
  - usare quello snapshot direttamente nei callsite Swift, con fallback solo se il payload e' incompleto
  - non cambiare il contratto dei result reducer gia' verdi
- Verifica post-fix:
  - `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testUpsertPatchSnapshotMutationUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testCloseFindingExecutionClosesMergedFinding -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesRoutesThroughPatchExecutionRuntime -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesFailsClosedWhenPatchRuntimeIsUnavailable`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewCommandRustBridge.swift,App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift,Native/RustCore/src/review_command/models.rs,Native/RustCore/src/review_command/mutator.rs,Native/RustCore/src/review_session/mod.rs --format text`
- Commit previsto: `refactor(review-patch): return canonical snapshots from rust mutations`

## Effetto osservato
- Le mutation patch possono ora restituire uno snapshot canonico gia' finalizzato dal core Rust.
- I callsite Swift patch-specifici smettono di ricostruire localmente `outcome` e `mutationSequence`.
- Il boundary review strict resta senza nuove violazioni.
