# P1 - Le precondizioni step-by-step del patch runtime review erano ancora owned da Swift

## Bug Fix Record
- Categoria: B
- Bug: [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift) validava ancora in Swift le precondizioni di ogni `step` del loop runtime patch.
- Sintomo:
  - lookup locale di `patch` e `finding`
  - guard locale su `providerRegistry`
  - branching locale per trasformare l'assenza di dati in `invalidPatch` / `providerUnavailable`
- Impatto: il runtime loop manteneva ancora logica di dominio Swift su un path fragile di orchestration step-by-step.
- Gravita': alta, perche' tocca il cuore del patch runtime review, dove i passaggi vengono avanzati e ridotti in sequenza.
- Steps to reproduce:
  1. Aprire [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift).
  2. Cercare il `switch step` dentro `executeWithRuntime(...)`.
  3. Verificare che patch/finding/providerRegistry siano ancora validati localmente step per step.
- Risultato attuale: il core Rust pianifica il runtime, ma una parte della validazione step-specifica e' ancora nel layer Swift.
- Risultato atteso: Swift deve ricevere dal core Rust un `step context` gia' validato e limitarsi a eseguire l'I/O concreto del passo.
- Causa probabile: il runtime patch era stato migrato per start/result reducer, ma non per la validazione locale delle dipendenze richieste da ogni step.
- Scope consentito:
  - [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift)
  - [models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/models.rs)
  - [step_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/step_context.rs)
  - [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/mod.rs)
  - [review_patch.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - panel runtime
  - provider execution reale
  - result reducer gia' migrati
- Moduli confinanti da verificare:
  - `CloseFindingExecution` tests
  - `PrepareVerifiedPatches` tests
  - patch runtime start/result bridges
- Test da aggiungere o aggiornare:
  - smoke `close_finding`
  - smoke `prepareVerifiedPatches` su route runtime e fail-closed
- Strategia di fix minimo:
  - aggiungere in Rust `build_step_context`
  - esporre il boundary `review_core_patch_build_step_context`
  - far usare al loop runtime il `step context` Rust per leggere `patch`, `finding` e `providerRegistryRequired`
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::step_context::tests`
  - `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testCloseFindingExecutionClosesMergedFinding -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testCloseFindingFailsWhenRustPatchRuntimeIsDisabled -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testCloseFindingFailsWhenPatchRuntimeResultBridgeIsUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesRoutesThroughPatchExecutionRuntime -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesFailsClosedWhenPatchRuntimeIsUnavailable`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift,Native/RustCore/src/review_patch/step_context.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/ffi/review_patch.rs,Native/RustCore/src/review_patch/models.rs --format text`
- Commit previsto: `refactor(review-patch): route runtime step context through rust`

## Effetto osservato
- Il loop runtime patch non valida piu' localmente in Swift le risorse richieste da ogni step.
- `patch`, `finding` e `providerRegistryRequired` sono ora derivati dal core Rust.
- Il boundary review strict resta senza nuove violazioni.
