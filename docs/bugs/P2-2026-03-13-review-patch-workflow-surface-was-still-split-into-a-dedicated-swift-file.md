# P2 - Il surface del patch workflow review era ancora in un file Swift dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewPanelStore+PatchWorkflow.swift` restava come file Swift non-UI dedicato per le action del patch workflow del panel review.
- Sintomo: `preparePatch`, `applyPatch`, `revalidatePatch`, `rollbackPatch`, `openPatchPullRequest` e `mergePatchPullRequest` vivevano ancora in un file separato pur appoggiandosi gia' ai servizi/runtime esistenti.
- Impatto: il backlog del prefisso review restava piu' alto e il patch workflow panel-side era ancora frammentato in due file store adiacenti.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `CodeReviewPanelStore+PatchWorkflow.swift`.
  2. Verificare che contenga solo action panel-side per il workflow patch.
  3. Notare che il file compare ancora come legacy non-UI nel conteggio del panel review.
- Risultato attuale: il patch workflow del panel restava in un file Swift dedicato.
- Risultato atteso: il surface panel-side del patch workflow deve vivere nei file store gia' esistenti adiacenti al runtime patch, senza file Swift non-UI dedicati superflui.
- Causa probabile: tranche precedenti hanno drenato launch/chat/history/git, ma non avevano ancora consolidato il surface patch panel-side.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - servizi patch engine-side
  - UI findings detail
  - nuove API Rust
- Moduli confinanti da verificare:
  - `CodeReviewPanelStore+PatchWorkflow+Execution.swift`
  - `CodeReviewPanelStore+Settings.swift`
  - `ReviewPanelFindingDetail+Sections.swift`
- Test da aggiungere o aggiornare:
  - validation review con budget gate attivo
  - targeted tests `SoloCodeAppTests` lanciati da `scripts/solocode-validate`
- Strategia di fix minimo:
  - spostare `preparePatch` e `applyPatch` in `PatchWorkflow+Execution`
  - spostare `revalidatePatch`, `rollbackPatch`, `openPatchPullRequest`, `mergePatchPullRequest` in `Settings`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PatchWorkflow+Execution.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Settings.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PatchWorkflow.swift,"Solo Code.xcodeproj/project.pbxproj",scripts/validate_rust_cutover_boundary.sh`
- Commit previsto: `refactor(review): merge patch workflow surface into existing store files`

## Fix applicato
- `preparePatch` e `applyPatch` spostati in `CodeReviewPanelStore+PatchWorkflow+Execution.swift`
- `revalidatePatch`, `rollbackPatch`, `openPatchPullRequest` e `mergePatchPullRequest` spostati in `CodeReviewPanelStore+Settings.swift`
- rimosso `CodeReviewPanelStore+PatchWorkflow.swift` dal filesystem e dal progetto Xcode

## Esito
- backlog panel review ridotto da `25` a `24`
- nessuna nuova violazione Swift non-UI
- build e test selettivi review restano verdi
