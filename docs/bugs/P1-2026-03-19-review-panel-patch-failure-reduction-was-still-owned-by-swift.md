# P1 - Il panel review riduceva ancora in Swift i failure path `patchFailed`

## Bug Fix Record
- Categoria: B
- Bug: [CodeReviewPanelStore+PatchWorkflow+Execution.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+PatchWorkflow+Execution.swift) e [CodeReviewPanelStore+CompletionFinalization.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+CompletionFinalization.swift) ricostruivano ancora in Swift i failure path `patchFailed`.
- Sintomo:
  - aggiornamento locale di `finding.status = .patchFailed`
  - aggiornamento locale di `patch.status`, `verifyStatus`, `applyMessage`, `conflicts`
  - ricostruzione locale di `outcome`
- Impatto: restava logica di dominio Swift nel panel runtime su failure path patch gia' coperti da reducer Rust nel command loop e nel finalization service.
- Gravita': alta, perche' tocca coerenza tra panel snapshot, registry live e semantics di patch failure.
- Steps to reproduce:
  1. Aprire [CodeReviewPanelStore+PatchWorkflow+Execution.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+PatchWorkflow+Execution.swift).
  2. Cercare `markPatchFailure(...)`.
  3. Verificare che finding/patch/outcome siano ancora aggiornati localmente in Swift.
- Risultato attuale: il panel non riusa ancora sistematicamente il reducer Rust `mark_patch_prepare_failed`.
- Risultato atteso: i failure path panel-side devono passare dal reducer Rust gia' esistente e ingerire lo snapshot ridotto.
- Causa probabile: il panel era rimasto allineato al vecchio fallback Swift anche dopo la migrazione del finalization path app-side.
- Scope consentito:
  - [ReviewPatchRuntimeFinalizationService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchRuntimeFinalizationService.swift)
  - [CodeReviewPanelStore+PatchWorkflow+Execution.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+PatchWorkflow+Execution.swift)
  - [CodeReviewPanelStore+CompletionFinalization.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+CompletionFinalization.swift)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - panel prompt/runtime chat
  - provider execution
  - patch result reducers Rust
- Moduli confinanti da verificare:
  - `CodeReviewPanelSessionScopingTests`
  - `ReviewPatchWorkflowServiceTests`
  - `ReviewPatchRuntimeFinalizationService`
- Test da aggiungere o aggiornare:
  - smoke sul dismiss/apply-fix panel path
  - smoke sul fail-closed di `prepareVerifiedPatches`
- Strategia di fix minimo:
  - rendere riusabile il reducer `reducePatchPrepareFailure(...)`
  - instradare `markPatchFailure(...)` e il catch del completion finalization attraverso quel reducer
  - mantenere solo l'append del messaggio UI in Swift
- Verifica post-fix:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelDismissFallbackUsesRustMutationAndMarksWontFix -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testApplyFixOnlyFailsTargetFinding -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesFailsClosedWhenPatchRuntimeIsUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesRoutesThroughPatchExecutionRuntime`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchRuntimeFinalizationService.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+PatchWorkflow+Execution.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+CompletionFinalization.swift --format text`
- Commit previsto: `refactor(review-panel): route patch failure reduction through rust`

## Effetto osservato
- I failure path panel-side su `patchFailed` usano ora il reducer Rust gia' esistente.
- Swift mantiene solo l'aggiornamento della UI e dei messaggi di sistema.
