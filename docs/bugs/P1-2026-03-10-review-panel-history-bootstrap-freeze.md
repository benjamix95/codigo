# P1 — Il tab `Findings History` poteva congelare la UI durante bootstrap persistence

## Bug Fix Record
- Categoria: A
- Bug: il caricamento del tab `Findings History` eseguiva la query storica PostgreSQL inline sul path `@MainActor` del panel review.
- Sintomo: aprendo il tab history mentre la persistence non era ancora pronta, l'app entrava in warning `Publishing changes from within view updates`, cicli `AttributeGraph` e blocchi su `__DISPATCH_WAIT_FOR_QUEUE__`.
- Impatto: freeze dell'interfaccia review, tab history non responsivo, percezione di app bloccata.
- Gravità: alta
- Steps to reproduce:
  1. avviare `Solo Code` con persistence PostgreSQL non ancora bootstrapata
  2. aprire il pannello Code Review e selezionare `History`
  3. eseguire `sample <pid-app> 5`
  4. osservare la catena `ReviewPanelFindingsHistoryTab -> refreshHistoricalFindings -> HistoricalFindingsQueryService -> PostgresPersistenceStore.ensureReady`
- Risultato attuale: il path UI del tab storico può chiamare direttamente una read che innesca bootstrap PostgreSQL e `waitUntilExit()` durante un update SwiftUI.
- Risultato atteso: il tab history deve caricare i dati fuori dal `@MainActor`, pubblicando solo il risultato finale e mantenendo fallback locale se il workspace non è disponibile.
- Causa probabile: `refreshHistoricalFindings()` viveva nel `CodeReviewPanelStore @MainActor` e chiamava `HistoricalFindingsQueryService.list(...)` in modo sincrono, senza boundary async separato.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+History.swift`
  - `Tests/SoloCodeAppTests/ReviewPanelFindingsHistoryTests.swift`
  - documentazione bug/changelog
- Non-scope:
  - refactor del layer persistence
  - modifica dello schema DB
  - redesign del tab History
- Moduli confinanti da verificare:
  - `ReviewPanelFindingsHistoryTab`
  - `CodeReviewPanelStore`
  - `HistoricalFindingsQueryService`
- Test da aggiungere o aggiornare:
  - regressione panel-level che popola `historyRecords` leggendo dallo store persistito del workspace
  - smoke sui test del lifecycle review già esistenti
- Strategia di fix minimo:
  - introdurre un boundary loader async dedicato al tab history
  - mantenere il merge DB-first + fallback snapshot invariato
  - evitare publish intermedi dopo un refresh diventato stantio
- Verifica post-fix:
  - `SoloCodeAppTests/ReviewPanelFindingsHistoryTests`
  - `SoloCodeAppTests/ReviewPanelLifecycleE2ETests`
  - `CoderEngineTests/HistoricalFindingsQueryServiceTests`
- Commit previsto: `fix(review): load history findings off the main actor`

## Evidenza
Sample raccolto sul processo app:

```text
ReviewPanelFindingsHistoryTab.body.getter
 -> CodeReviewPanelStore.refreshHistoricalFindings()
 -> HistoricalFindingsQueryService.list(query:)
 -> PostgresPersistenceStore.readHistoricalFindings(query:)
 -> PostgresPersistenceStore.ensureReady()
 -> ManagedPostgresService.runProcess(...).waitUntilExit()
 -> NSConcreteTask.waitUntilExit
 -> ...
 -> PostgresPersistenceStore.readVerifiedFindingsEnvelope(sessionId:)
 -> PostgresPersistenceStore.ensureReady()
 -> __DISPATCH_WAIT_FOR_QUEUE__
```
