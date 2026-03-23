# P1 - La riduzione del failure `prepare_patch` nel review patch finalization era ancora owned da Swift

## Bug Fix Record
- Categoria: A
- Bug: `ReviewPatchRuntimeFinalizationService.defaultPrepareVerifiedPatches(...)` e il path auto-prepare del command loop ricostruivano ancora in Swift il fallimento di `prepare_patch`, marcando finding e commenti localmente.
- Sintomo:
  - `patchFailed`
  - commento `"Patch preview non disponibile: ..."`
  - outcome aggiornato
  venivano ancora applicati nel layer app-side invece che dal reducer canonico Rust della sessione review.
- Impatto: anche dopo il porting di target selection, il patch finalization manteneva ancora una mutazione di dominio Swift sul failure path piu' comune.
- Gravita': alta, perche' tocca stato finding, outcome summary e finalizzazione patch automatica.
- Steps to reproduce:
  1. Ispezionare [ReviewPatchRuntimeFinalizationService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchRuntimeFinalizationService.swift).
  2. Verificare che nel `catch` di `prepare_patch` il codice ricrei finding/commenti direttamente in Swift.
  3. Eseguire i test app-side del patch finalization.
- Risultato attuale: il failure reducer di `prepare_patch` non e' ancora Rust-owned.
- Risultato atteso: il layer app-side deve delegare al core Rust la mutazione canonica del finding quando la patch preview fallisce.
- Causa probabile: il path d’errore era stato mantenuto in Swift per sbloccare prima il runtime patch.
- Scope consentito:
  - `Native/RustCore/src/review_session/apply.rs`
  - `App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchRuntimeFinalizationService.swift`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - esecuzione patch runtime
  - merge/apply/revalidate workflow
  - panel runtime
- Moduli confinanti da verificare:
  - `ReviewPatchWorkflowServiceTests`
  - `SoloCodeAppCodeReviewCommandLoopTests`
  - `CodeReviewSessionState`
- Test da aggiungere o aggiornare:
  - regression app-side su failure reducer `prepareVerifiedPatches`
  - smoke command-loop auto-prepare
- Strategia di fix minimo:
  - introdurre nel reducer session Rust l’operazione `mark_patch_prepare_failed`
  - sostituire il fallback Swift nel finalization service con una chiamata a `review_core_session_apply_action`
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testAutoPrepareEligibleFindingIdsOnlyReturnsVerifiedFilteredOriginsWithoutExistingPatch -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testAutoPrepareEligibleFindingIdsFailsClosedWhenRustRuntimeIsDisabled -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesRoutesThroughPatchExecutionRuntime -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesFailsClosedWhenPatchRuntimeIsUnavailable`
- Commit previsto: `refactor(review-finalize): route prepare failure reduction through rust`

## Effetto osservato
- Il failure `prepare_patch` non viene piu' ricostruito localmente nel layer Swift.
- Lo stato `patchFailed`, i commenti di errore e l’outcome passano ora dal reducer session Rust.
