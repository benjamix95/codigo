# 2026-03-10 — Findings History enterprise e persistenza completa lifecycle

## Cosa cambia
- nuovo tab `Findings History` nel Code Review panel, separato da `Findings` live e `Timeline`
- storico globale `workspace-scoped` dei finding, con:
  - bug e security
  - finding risolti, patchati, rollbackati, chiusi
  - ultimi stati patch/revalidation
  - `Resume Queue` per finding non chiusi
- detail storico dedicato con:
  - summary
  - status lifecycle
  - patch/revalidation state
  - chronology degli eventi persistiti
  - azione `Resume` per continuare un finding incompleto

## Persistence / DB
- aggiunto query layer storico DB-first:
  - `HistoricalFindingsQueryService`
  - `PostgresPersistenceStore+HistoricalFindings`
- `persistCodeReviewSnapshot` ora:
  - crea/upserta la `workspace` prima della `review_session`
  - persiste sempre l’envelope canonical dei verified findings anche se lo snapshot non lo include già embeddato
- `persistVerifiedFindingsEnvelope` ora collega meglio il lifecycle nel DB:
  - valorizza `pipeline_runs.review_session_id`
  - valorizza `findings.origin_run_id`

## UI / Panel
- aggiunti nuovi modelli filtro/history per il panel
- il nuovo tab `Findings History` usa il DB come source of truth e integra fallback snapshot solo quando la persistence non è disponibile
- il resume di un finding storico genera una nuova review `workspace` con prompt guidato che include stato, patch e verdict precedenti

## Test
- `CoderEngineTests/HistoricalFindingsQueryServiceTests`
- `SoloCodeAppTests/ReviewPanelFindingsHistoryTests`
- regressioni verdi su:
  - `SoloCodeAppTests/ReviewPanelLifecycleE2ETests`
  - `CoderEngineTests/VerifiedFindingsStatusServiceTests`
  - `CoderEngineTests/BugHunterHandlerTests`

## Note
- i nuovi file sono stati aggiunti esplicitamente al progetto Xcode e ai target corretti
- nessun archivio parallelo: il DB PostgreSQL/shared persistence resta la source of truth dello storico enterprise
