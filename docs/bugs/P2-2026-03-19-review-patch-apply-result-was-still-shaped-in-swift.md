# P2 — review patch apply result ancora modellato in Swift

## Categoria
- `B` importante ma non bloccante

## Bug
- Dopo il cutover di `prepare_context` e `verify_result`, il lifecycle `apply_patch` continuava ad avere il risultato canonico dell’artifact modellato in Swift.

## Sintomo
- `ReviewPatchWorkflowService+ApplyLifecycle.swift` eseguiva `git apply --3way` e la validation, ma poi decideva localmente:
  - `status = .applied`
  - `verifyStatus = .verified`
  - `validationRunId`
  - `validationStatus`
  - `validationSummary`
  - `rollbackRef`
  - `applyMessage`

## Impatto
- Ownership ancora sdoppiata sul passo più importante del patch workflow.
- Rust orchestrava planner, runtime state, prepare context e verify result, ma non il risultato finale di `apply_patch`.
- Il batch successivo su rollback/revalidate sarebbe partito da una base ancora Swift-owned.

## Gravità
- `P2`

## Steps to reproduce
1. Eseguire `apply_patch` o `apply_fix`.
2. Osservare che l’esecuzione Git e la validation avvengono in Swift.
3. Prima del fix, osservare che anche il risultato finale dell’artifact applicato veniva modellato in Swift.

## Risultato attuale
- Prima del fix, Rust non partecipava allo shaping del risultato canonico di `apply_patch`.

## Risultato atteso
- L’esecuzione `git apply` e `runValidation` può restare Swift in questo batch, ma il risultato finale dell’artifact deve essere derivato dal review core Rust.

## Causa probabile
- Il cutover patch era arrivato a planner/runtime/prepare/verify, ma non ancora al risultato `apply_patch`.

## Scope consentito
- `Native/RustCore/src/review_patch/{apply_result.rs,models.rs,mod.rs}`
- `Native/RustCore/src/ffi/review_patch.rs`
- `App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift`
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`

## Non-scope
- Porting completo di `git apply`, validation, rollback, merge o conflict resolution in Rust
- MCP ownership
- UI panel

## Moduli confinanti da verificare
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`

## Test da aggiungere o aggiornare
- test Rust sul builder `apply_result`
- test Swift Rust-gated del risultato applicato
- test fail-closed se il runtime `apply_result` non risponde

## Strategia di fix minimo
- aggiungere builder Rust per il risultato di `apply_patch`
- fare chiamare quel builder a `ReviewPatchWorkflowService.applyPatch(...)`
- lasciare in Swift solo:
  - `git apply --3way`
  - validation
  - reverse apply su failure

## Verifica post-fix
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`

## Commit previsto
- `refactor(review-patch): derive apply result in rust`
