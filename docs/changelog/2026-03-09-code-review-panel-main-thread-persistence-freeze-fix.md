# 2026-03-09 — Fix freeze panel review causato da persistenza PostgreSQL sul main thread

## Obiettivo
Evitare che l’avvio o l’aggiornamento della code review blocchi la UI mentre la persistenza MCP/PostgreSQL esegue bootstrap e `psql`.

## Modifiche
- aggiornato `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore.swift`
  - introdotto `TaskActivityPersistenceBridge` nello stesso file per evitare modifiche al target Xcode
  - bridge dedicato con coda seriale `utility`
  - `TaskActivityStore` riceve il bridge via init, con default `.shared`
  - `flush()` disponibile per test deterministici
- aggiornato `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+CodeReview.swift`
  - `ingestCodeReviewSnapshot` non chiama più direttamente `MCPSharedState.writeCodeReviewSnapshot`
  - il write review cross-process viene delegato al bridge asincrono
- aggiornato `Tests/SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests.swift`
  - verifica che l’ingest non persista inline
  - verifica che l’ordine dei write resti seriale

## Evidenza diagnostica
Sample del processo app bloccato (`pid 30884`) raccolto con:

```bash
sample 30884 5 -file /tmp/solo-code-main.sample.txt
```

Stack principale osservato:

```text
CodeReviewPanelStore.startReview
 -> TaskActivityStore.ingestCodeReviewSnapshot
 -> MCPSharedState.writeCodeReviewSnapshot
 -> PostgresPersistenceStore.ensureReady
 -> ManagedPostgresService.runProcess(...).waitUntilExit
```

## Validazione prevista
Eseguire su macOS con `xcodebuild`:

```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests \
  -only-testing:SoloCodeAppTests/CodeReviewPanelChatPromptRoutingTests \
  -only-testing:CoderEngineTests/PersistenceBootstrapIntegrationTests \
  -only-testing:CoderEngineTests/MCPSharedStatePostgresFallbackTests/testVerifiedFindingsReadsFromPostgresWhenLegacyFilesAreMissing
```

## Note
- Fix confinato al bridge UI -> persistence della review.
- Nessun refactor del layer PostgreSQL oltre al fix SQL già in corso per `pipeline_runs`.
