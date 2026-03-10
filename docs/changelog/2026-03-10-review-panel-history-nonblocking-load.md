# 2026-03-10 — History review non bloccante

## Obiettivo
Evitare che il tab `Findings History` del pannello review blocchi la UI quando la persistence PostgreSQL deve ancora bootstrapparsi.

## Modifiche
- aggiornato `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+History.swift`
  - `refreshHistoricalFindings()` ora carica il DB tramite `ReviewPanelHistoricalFindingsLoader`
  - il loader usa `Task.detached(priority: .userInitiated)` per spostare la read fuori dal `@MainActor`
  - aggiunta guardia `refreshKey` per evitare publish di risultati stantii dopo refresh concorrenti
  - mantenuto invariato il fallback snapshot locale quando manca `workspaceId`
- aggiornato `Tests/SoloCodeAppTests/ReviewPanelFindingsHistoryTests.swift`
  - aggiunta regressione che persiste uno snapshot review nel DB di test
  - il test verifica che `refreshHistoricalFindings()` popoli correttamente `historyRecords` dal workspace persistito
- documentato il bug in `docs/bugs/P1-2026-03-10-review-panel-history-bootstrap-freeze.md`

## Validazione eseguita
```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests

xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests \
  -only-testing:SoloCodeAppTests/ReviewPanelLifecycleE2ETests \
  -only-testing:CoderEngineTests/HistoricalFindingsQueryServiceTests
```

## Note
- Fix confinato al path del tab History.
- Nessun cambiamento del modello dati persistito.
- Il bootstrap FK di `VerifiedFindings` è stato gestito in un commit separato.
