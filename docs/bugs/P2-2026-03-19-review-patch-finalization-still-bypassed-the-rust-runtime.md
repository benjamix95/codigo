# P2 — review patch finalization bypassava ancora il runtime patch Rust

## Categoria
- `B` importante ma non bloccante

## Bug
- La finalizzazione patch del review panel e del provider runtime continuava ad avere un path Swift duplicato che costruiva e verificava la patch preview senza passare da `VerifiedFindingsPatchExecutionService` e quindi senza riusare il runtime patch Rust.

## Sintomo
- `ReviewPatchRuntimeFinalizationService.defaultPrepareVerifiedPatches(...)` chiamava direttamente `ReviewPatchWorkflowService.preparePatch(...)` e `verifyPatch(...)`.
- Il path `prepare_patch` del command/runtime e quello di finalizzazione deferred non condividevano lo stesso boundary.

## Impatto
- Ownership ancora sdoppiata su `prepare_patch` e `verify_patch`.
- Il deferred auto-prepare poteva divergere dal patch runtime centrale.
- I failure mode del runtime patch non erano uniformi tra command path e panel/provider finalization path.

## Gravità
- `P2`

## Steps to reproduce
1. Completare una review con finding verificati e auto-prepare attivo.
2. Osservare che la finalizzazione panel/provider invoca `ReviewPatchRuntimeFinalizationService.prepareVerifiedPatches(...)`.
3. Prima del fix, quel path costruiva la preview patch localmente invece di passare dall’executor patch centrale.

## Risultato attuale
- Prima del fix, il path di finalizzazione usava direttamente `ReviewPatchWorkflowService`.

## Risultato atteso
- Anche la finalizzazione deferred deve passare dal runtime patch centrale, con lo stesso failure mode e lo stesso boundary del command path.

## Causa probabile
- Cutover progressivo lasciato con un path locale temporaneo per l’auto-prepare panel/provider.

## Scope consentito
- `App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchRuntimeFinalizationService.swift`
- `App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift`
- test mirati panel/provider finalization e patch service

## Non-scope
- Porting completo di `apply_patch`, `rollback_patch`, `merge_pr`, `resolve_conflicts`
- MCP ownership
- UI Swift del panel

## Moduli confinanti da verificare
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`
- `Tests/SoloCodeAppTests/ReviewPanelProviderSelectionTests.swift`

## Test da aggiungere o aggiornare
- test che `prepareVerifiedPatches(...)` instrada attraverso `VerifiedFindingsPatchExecutionService`
- test fail-closed sul path di finalizzazione quando il runtime patch non è disponibile
- test provider/panel che continua a finalizzare correttamente con handler di test

## Strategia di fix minimo
- riusare `VerifiedFindingsPatchExecutionService.execute(action: "prepare_patch", ...)` anche nella finalizzazione deferred
- aggiungere supporto a un execution provider diretto nell’executor patch centrale
- risolvere il provider solo quando serve davvero, non in anticipo per azioni che non lo richiedono

## Verifica post-fix
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests`

## Commit previsto
- `refactor(review-patch): route deferred patch preparation through runtime`
