# P1 - Il panel review manteneva ancora un fallback locale nel patch failure path

## Bug Fix Record
- Categoria: B
- Bug: [CodeReviewPanelStore+PatchWorkflow+Execution.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+PatchWorkflow+Execution.swift) manteneva ancora un fallback locale in `markPatchFailure(...)` quando il reducer Rust `mark_patch_prepare_failed` non restituiva uno snapshot.
- Sintomo:
  - mutazione locale di `finding.status = .patchFailed`
  - mutazione locale di `patch.status`, `verifyStatus`, `applyMessage`, `conflicts`
  - ricostruzione locale di `events` e `outcome`
- Impatto: restava logica review Swift nel panel runtime, proprio nel failure path patch panel-side.
- Gravita': alta, perche' tocca il bridge UI/runtime e la coerenza dello snapshot visualizzato nel panel.
- Steps to reproduce:
  1. Aprire [CodeReviewPanelStore+PatchWorkflow+Execution.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+PatchWorkflow+Execution.swift).
  2. Cercare `markPatchFailure(...)`.
  3. Verificare il fallback locale dopo `reducePatchPrepareFailure(...)`.
- Risultato attuale: il panel non era ancora completamente fail-closed su quel path.
- Risultato atteso: il panel deve accettare solo lo snapshot ridotto dal reducer Rust o non mutare lo snapshot quando il reducer è indisponibile.
- Causa probabile: il path storico teneva compatibilita' con la fase pre-migrazione, e il test positivo era implicitamente dipendente dal flush asincrono di `scheduleCodeReviewSnapshotIngest(...)`.
- Scope consentito:
  - [CodeReviewPanelStore+PatchWorkflow+Execution.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+PatchWorkflow+Execution.swift)
  - [CodeReviewPanelSessionScopingTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CodeReviewPanelSessionScopingTests.swift)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - reducer Rust `mark_patch_prepare_failed`
  - patch workflow services app-side
  - verified findings runtime
- Moduli confinanti da verificare:
  - `CodeReviewPanelSessionScopingTests`
  - strict cutover gate review
  - `TaskActivityStore.scheduleCodeReviewSnapshotIngest(...)`
- Test da aggiungere o aggiornare:
  - regression test fail-closed quando `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`
  - il test positivo panel-side deve attendere esplicitamente il flush asincrono dell’ingest
- Strategia di fix minimo:
  - rimuovere il fallback locale in `markPatchFailure(...)`
  - aggiungere il test fail-closed
  - stabilizzare il test positivo con una breve attesa esplicita dopo `applyFix(...)`
- Verifica post-fix:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelApplyFixFailsClosedWithoutWorkspaceAndDoesNotTouchOtherFindings -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelApplyFixDoesNotMutateSnapshotWhenRustFailureReducerIsUnavailable`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+PatchWorkflow+Execution.swift --format text`
- Commit previsto: `refactor(review-panel): fail closed on patch failure reduction`

## Effetto osservato
- Il panel patch failure path non ricostruisce più localmente lo snapshot.
- Con reducer Rust indisponibile, il panel non muta più lo snapshot.
- Il test positivo panel-side è stato reso deterministico rispetto al flush asincrono dell’ingest.
