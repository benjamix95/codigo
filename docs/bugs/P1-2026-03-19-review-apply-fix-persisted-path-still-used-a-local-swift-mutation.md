# P1 - Il path persisted `apply_fix` usava ancora una mutazione Swift locale

## Bug Fix Record
- Categoria: B
- Bug: [ReviewPatchWorkflowService+ApplyLifecycle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift) manteneva ancora una mutazione Swift locale nel path persisted di `markFindingFixApplied(...)`.
- Sintomo:
  - fallback locale che impostava `finding.status = .fixApplied`
  - append locale dell'evento `.findingFixApplied`
  - ricostruzione locale di `outcome`
- Impatto: restava logica review Swift nel path app-side di `apply_fix`, nonostante il mutator Rust `review_core_command_mutate_snapshot` supporti già l'azione canonica.
- Gravita': alta, perche' tocca il command/app lifecycle su snapshot persisted e la coerenza tra MCP shared state e review registry.
- Steps to reproduce:
  1. Aprire [ReviewPatchWorkflowService+ApplyLifecycle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift).
  2. Cercare `markFindingFixApplied(...)`.
  3. Verificare la closure locale passata a `persistReviewSnapshotMutation(...)`.
- Risultato attuale: il path persisted `apply_fix` non era ancora pienamente passivo verso Rust.
- Risultato atteso: lo snapshot persisted deve essere mutato solo dal mutator Rust `apply_fix`, oppure fallire chiuso se il runtime non e' disponibile.
- Causa probabile: il callsite app-side era rimasto in modalità compatibilità pre-cutover.
- Scope consentito:
  - [ReviewPatchWorkflowService+ApplyLifecycle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift)
  - [SoloCodeAppCodeReviewCommandLoopTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests.swift)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - live session registry path
  - patch workflow runtime reducers
  - panel runtime
- Moduli confinanti da verificare:
  - `SoloCodeAppCodeReviewCommandLoopTests`
  - persisted review snapshot mutation path
- Test da aggiungere o aggiornare:
  - regression test positivo su snapshot persisted
  - regression test fail-closed con runtime Rust disabilitato
- Strategia di fix minimo:
  - sostituire la mutazione Swift locale con `ReviewCommandRustBridge.mutateSnapshot(... action: \"apply_fix\" ...)`
  - richiedere `mutation.snapshot` come unico success path canonico
- Verifica post-fix:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testMarkFindingFixAppliedUsesRustMutationForPersistedSnapshot -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testMarkFindingFixAppliedFailsClosedWhenRustMutationRuntimeIsDisabled`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift --format text`
- Commit previsto: `refactor(review-apply-fix): route persisted mutation through rust`

## Effetto osservato
- Il path persisted `apply_fix` usa ora solo lo snapshot canonico restituito dal mutator Rust.
- Quando il runtime Rust è disabilitato, la mutazione fallisce chiuso e lo snapshot resta invariato.
