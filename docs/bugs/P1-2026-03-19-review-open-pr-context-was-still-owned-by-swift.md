# P1 - Il contesto `open_pr` review era ancora owned da Swift

## Bug Fix Record
- Categoria: B
- Bug: il runtime patch review costruiva ancora in Swift il contesto semantico di `open_pr`, cioe' `title/body` della pull request, dentro [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift).
- Sintomo:
  - `title` derivato localmente da `filePath`
  - `body` derivato localmente da `message + verificationReport`
  - nessun boundary Rust dedicato per questo step del patch workflow
- Impatto: il workflow patch non era ancora completamente Rust-owned sul passo `open_pr`; inoltre il nuovo bridge risultava inizialmente non verificabile da test per una visibilita' Swift incompleta.
- Gravita': alta, perche' tocca il command lifecycle del patch workflow review e blocca la chiusura del porting semantico app-side.
- Steps to reproduce:
  1. Aprire [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift).
  2. Cercare lo step runtime `case "open_pr"`.
  3. Verificare che `title/body` siano ancora costruiti in Swift dal `finding`.
- Risultato attuale: lo step `open_pr` dipende ancora da semantica locale Swift.
- Risultato atteso: Swift deve solo richiedere al core Rust il contesto PR e fallire chiuso se il boundary non risponde.
- Causa probabile: il patch workflow era stato migrato per prepare/apply/verify/revalidate/rollback, ma lo step PR aveva mantenuto l'ultima derivazione semantica locale.
- Scope consentito:
  - [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift)
  - [review_patch.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs)
  - [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/mod.rs)
  - [pr_result_models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/pr_result_models.rs)
  - [open_pr_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/open_pr_context.rs)
  - [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - apertura PR reale verso provider esterni
  - merge/conflict resolution
  - panel runtime
- Moduli confinanti da verificare:
  - `ReviewPatchWorkflowServiceTests`
  - `CodigoAppCodeReviewCommandLoopTests`
  - boundary Rust `review_patch`
- Test da aggiungere o aggiornare:
  - regression app-side che verifichi `title/body` via boundary Rust
  - smoke app-side sul failure path `prepareVerifiedPatches`
- Strategia di fix minimo:
  - aggiungere request/response tipizzati per `open_pr` context nel modulo Rust `review_patch`
  - esporre il boundary `review_core_patch_build_open_pr_context`
  - sostituire la derivazione Swift con una chiamata fail-closed al core Rust
  - rendere il risultato esponibile al test senza reintrodurre logica Swift
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::open_pr_context::tests`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testAutoPrepareEligibleFindingIdsOnlyReturnsVerifiedFilteredOriginsWithoutExistingPatch -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testAutoPrepareEligibleFindingIdsFailsClosedWhenRustRuntimeIsDisabled -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesRoutesThroughPatchExecutionRuntime -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesFailsClosedWhenPatchRuntimeIsUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testOpenPRContextUsesRustContextBuilder`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift,Native/RustCore/src/ffi/review_patch.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/review_patch/pr_result_models.rs,Native/RustCore/src/review_patch/open_pr_context.rs,Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift --format text`
- Commit previsto: `refactor(review-patch): route open pr context through rust`

## Effetto osservato
- Lo step `open_pr` del patch workflow delega ora al core Rust la derivazione di `title/body`.
- Il bridge Swift fallisce chiuso se il runtime Rust non risponde o restituisce un payload incompleto.
- Esiste una regressione app-side dedicata che verifica il contratto osservabile del contesto PR.
