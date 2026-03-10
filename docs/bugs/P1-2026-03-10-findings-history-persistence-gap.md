# P1 — mancava uno storico persistito enterprise per finding review/bug/security

## Bug Fix Record
- Categoria: A
- Bug: i finding review/bug/security non avevano una superficie persistita e consultabile enterprise-grade per cronologia globale workspace, resume queue e continuità dei fix nel tempo.
- Sintomo: il panel esponeva solo `Findings` live e `Timeline` della sessione corrente; una volta chiusa o cambiata la review mancava una vista DB-first unica dei finding risolti, patchati, rollbackati o ancora incompleti.
- Impatto: perdita di tracciabilità storica, impossibilità pratica di riprendere in futuro finding non chiusi, UX non adeguata per uso enterprise e audit trail.
- Gravità: alta
- Steps to reproduce:
  1. Avviare una review con finding bug/security.
  2. Applicare patch o lasciare finding incompleti.
  3. Tornare più tardi sul progetto o aprire una nuova sessione review.
  4. Osservare che non esiste un tab storico globale con stato, patch, revalidation e resume queue.
- Risultato attuale: il DB aveva già tabelle `pipeline_runs`, `findings`, `verification_reports`, `patch_artifacts`, `revalidation_reports`, `pipeline_events`, ma l’app non esponeva una query/workflow storico globale e alcuni write path non completavano la persistenza enterprise.
- Risultato atteso: tutti i finding finiscono nel DB con lifecycle completo; il panel offre un tab `Findings History` globale del workspace con cronologia, stati e coda di ripresa.
- Causa probabile:
  - nessun query layer storico workspace-scoped sopra PostgreSQL
  - `persistCodeReviewSnapshot` non persistiva sempre l’envelope canonical se non già embeddato
  - write path review mancava dell’upsert `workspace`
  - `pipeline_runs.review_session_id` e `findings.origin_run_id` non venivano popolati
- Scope consentito:
  - persistence review/verified findings
  - query storiche DB-first
  - tab Code Review history e relativo detail/resume
  - test mirati persistence/history
  - documentazione bug/changelog
- Non-scope:
  - refactor completo del timeline live
  - redesign totale del detail finding live
  - nuovo archivio parallelo fuori dal DB esistente
- Moduli confinanti da verificare:
  - `PostgresPersistenceStore+ReviewAndPlan`
  - `PostgresPersistenceStore+VerifiedFindings`
  - query `HistoricalFindings`
  - `CodeReviewPanelStore`
  - `ReviewPanelLifecycle`
- Test da aggiungere o aggiornare:
  - `CoderEngineTests/HistoricalFindingsQueryServiceTests`
  - `SoloCodeAppTests/ReviewPanelFindingsHistoryTests`
  - smoke regressione su `ReviewPanelLifecycleE2ETests`
  - smoke regressione su `BugHunterHandlerTests`
  - smoke regressione su `VerifiedFindingsStatusServiceTests`
- Strategia di fix minimo:
  - aggiungere query storica workspace-scoped sul DB esistente
  - completare il write path review per persistire sempre envelope + workspace FK + linking run/finding
  - introdurre tab `Findings History` separato dal `Timeline`
  - esporre resume queue e resume prompt guidato per finding incompleti
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/HistoricalFindingsQueryServiceTests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests -only-testing:SoloCodeAppTests/ReviewPanelLifecycleE2ETests -only-testing:CoderEngineTests/VerifiedFindingsStatusServiceTests -only-testing:CoderEngineTests/BugHunterHandlerTests`
- Commit previsto: `feat(review): persist and surface historical findings`

## Note
- Il nuovo storico è `workspace globale`, DB-first, con fallback in-memory limitato solo quando il DB non è disponibile.
- `Timeline` live e `Findings History` restano separati per evitare confusione tra stream operativo e audit trail persistito.
