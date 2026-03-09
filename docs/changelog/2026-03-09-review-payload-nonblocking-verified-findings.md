# 2026-03-09 — Review payload non-blocking per VerifiedFindings

## Obiettivo
Rimuovere il blocco del panel review/main chat causato dalla read `VerifiedFindings` sincrona durante l’assemblaggio del payload UI.

## Modifiche
- `TaskActivityStore+VerifiedFindings` ora costruisce il payload review usando:
  - envelope `verifiedFindings` già embedded nello snapshot
  - envelope in-memory già presente nello store
  - fallback `VerifiedFindingsSessionSyncService.sync(snapshot:)`
- replay e security gate continuano a essere calcolati tramite `VerifiedFindingsService.resolve(recovered:)`, ma senza passare da `MCPSharedState` o PostgreSQL
- aggiunta regressione che verifica il fallback `synced_from_snapshot` quando lo snapshot non contiene l’envelope embedded
- preservata la regressione che verifica il source `embedded_snapshot` quando l’envelope è già presente nello snapshot

## File toccati
- `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+VerifiedFindings.swift`
- `Tests/SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests.swift`
- `docs/bugs/P1-2026-03-09-review-payload-verified-findings-read-blocked-main-thread.md`

## Validazione
Eseguita con `xcodebuild` locale sul workspace:

```bash
xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' \
  -destination 'platform=macOS' \
  -only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests/testCodeReviewPayloadIncludesVerifiedFindingsFacadeFields \
  -only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests/testCodeReviewPayloadBuildsVerifiedFindingsFromSnapshotWithoutPersistenceRead
```

Esito:
- 2 test eseguiti
- 0 failure

## Note
Il fix è confinato al path UI del payload review. Non cambia il facade shared `VerifiedFindingsService` né il layer persistence.
