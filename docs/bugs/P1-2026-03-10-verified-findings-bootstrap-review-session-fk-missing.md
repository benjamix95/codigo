# P1 — Bootstrap legacy `VerifiedFindings` rompeva le FK `review_session_id` e `origin_run_id`

## Bug Fix Record
- Categoria: A
- Bug: l'import legacy PostgreSQL di `VerifiedFindingsSessionEnvelope` scriveva `pipeline_runs.review_session_id` e `findings.origin_run_id` con riferimenti non garantiti dal bootstrap.
- Sintomo: `PersistenceBootstrapIntegrationTests.testBootstrapImportsLegacyVerifiedFindingsAndPlanState()` falliva con errore FK durante `bootstrapIfNeeded()`.
- Impatto: il bootstrap enterprise verso PostgreSQL si interrompeva, impedendo il replay del canonical snapshot e lasciando il sistema sul fallback legacy JSON.
- Gravità: alta
- Steps to reproduce:
  1. salvare un envelope legacy con `sessionId = session-import` e `run.id = run-import`
  2. non salvare alcuna `review_session` legacy corrispondente
  3. eseguire `PersistenceBootstrapService(store: ...).bootstrapIfNeeded()`
  4. osservare il fallimento durante `persistVerifiedFindingsEnvelope(...)`
- Risultato attuale:
  - `pipeline_runs.review_session_id` veniva valorizzato sempre con `sessionId`, anche quando `review_sessions(sessionId)` non esisteva
  - `findings.origin_run_id` veniva valorizzato con `sessionId` invece che con l'`id` del run persistito
- Risultato atteso:
  - `review_session_id` deve essere valorizzato solo se esiste davvero una review session compatibile
  - `origin_run_id` deve puntare a un `pipeline_runs.id` reale oppure restare `NULL`
- Causa probabile: il writer canonical assumeva che review session e run fossero sempre 1:1 con `sessionId`, ma il bootstrap legacy importa anche envelope standalone senza snapshot review.
- Scope consentito:
  - `Engine/CoderEngine/Sources/PersistenceCore/PostgresPersistenceStore+VerifiedFindings.swift`
  - `Tests/CoderEngineTests/Persistence/PersistenceBootstrapIntegrationTests.swift`
  - documentazione bug/changelog
- Non-scope:
  - refactor del bootstrap completo
  - modifica dello schema
  - cambiamenti ai payload MCP legacy
- Moduli confinanti da verificare:
  - `LegacyPersistenceImportService`
  - `PersistenceBootstrapService`
  - query store su `pipeline_runs` / `findings`
- Test da aggiungere o aggiornare:
  - regressione che verifica bootstrap verde con envelope standalone
  - assert su `pipeline_runs.review_session_id = NULL` quando manca la review session
  - assert su `findings.origin_run_id = run-import`
- Strategia di fix minimo:
  - risolvere `review_session_id` via subquery idempotente che collega la review solo se già esiste
  - risolvere `origin_run_id` al run univoco del canonical snapshot, altrimenti `NULL`
- Verifica post-fix:
  - `PersistenceBootstrapIntegrationTests.testBootstrapImportsLegacyVerifiedFindingsAndPlanState()` verde
  - suite mirata history/review ancora verde
- Commit previsto: `fix(persistence): guard legacy verified findings foreign keys during bootstrap`

## Evidenza
Errore osservato nel test:

```text
insert or update on table "pipeline_runs" violates foreign key constraint "pipeline_runs_review_session_id_fkey"
DETAIL: Key (review_session_id)=(session-import) is not present in table "review_sessions".
```

Failure successiva prevenuta dallo stesso fix:

```text
insert or update on table "findings" violates foreign key constraint "findings_origin_run_id_fkey"
DETAIL: Key (origin_run_id)=(session-import) is not present in table "pipeline_runs".
```
