# 2026-03-10 — Fix FK bootstrap legacy `VerifiedFindings`

## Obiettivo
Far completare il bootstrap PostgreSQL quando un envelope legacy `VerifiedFindings` contiene run canonici ma non esiste ancora una `review_session` omologa.

## Modifiche
- aggiornato `Engine/CoderEngine/Sources/PersistenceCore/PostgresPersistenceStore+VerifiedFindings.swift`
  - `pipeline_runs.review_session_id` ora viene risolto con una subquery verso `review_sessions`
  - se la review session non esiste, il campo resta `NULL` invece di rompere la FK
  - `findings.origin_run_id` non usa più `sessionId`: punta al run univoco del canonical snapshot quando disponibile, altrimenti `NULL`
- aggiornato `Tests/CoderEngineTests/Persistence/PersistenceBootstrapIntegrationTests.swift`
  - il test di bootstrap verifica ora anche il valore persistito di `pipeline_runs.review_session_id`
  - aggiunta verifica su `findings.origin_run_id = run-import`
- documentato il bug in `docs/bugs/P1-2026-03-10-verified-findings-bootstrap-review-session-fk-missing.md`

## Validazione eseguita
```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/PersistenceBootstrapIntegrationTests/testBootstrapImportsLegacyVerifiedFindingsAndPlanState

xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests \
  -only-testing:SoloCodeAppTests/ReviewPanelLifecycleE2ETests \
  -only-testing:CoderEngineTests/HistoricalFindingsQueryServiceTests
```

## Note
- Fix confinato al writer di persistence bootstrap legacy.
- Nessun cambiamento allo schema PostgreSQL.
- Il rumore `pid 400` / `WindowServer` e i warning MCP discovery restano separati da questo bug.
