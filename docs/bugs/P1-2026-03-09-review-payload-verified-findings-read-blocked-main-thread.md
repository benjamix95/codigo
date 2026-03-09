# Bug Fix Record
- Categoria: A - Critico
- Bug: `TaskActivityStore.codeReviewPayload` risolveva `VerifiedFindings` leggendo persistence shared sul path UI della review chat
- Sintomo: panel chat review bloccato o non responsivo mentre il main thread entra in `PostgresPersistenceStore.ensureReady()` durante la costruzione del payload
- Impatto: freeze del panel review/main chat, ritardo nella comparsa dello stato review e possibile cascata con bootstrap PostgreSQL o fallback legacy
- Gravità: P1
- Steps to reproduce:
  1. avviare `Solo Code` con review snapshot privo di envelope `verifiedFindings` embedded
  2. aprire il panel chat review o forzare `resolveRuntimeProvider`
  3. campionare il PID mentre la UI è bloccata
  4. osservare lo stack `TaskActivityStore.codeReviewPayload -> VerifiedFindingsService.resolve -> MCPSharedState.readVerifiedFindingsEnvelope -> PostgresPersistenceStore.ensureReady`
- Risultato attuale: il payload review esegue una read sincrona di `VerifiedFindings` che può avviare bootstrap persistence e process spawn
- Risultato atteso: il payload UI deve usare solo stato già in memoria oppure ricostruire dall’istantanea review senza toccare persistence cross-process
- Causa probabile: il facade `VerifiedFindingsService.resolve(snapshot:)` è corretto per backend/shared state, ma non è sicuro sul path UI se il payload deve restare non bloccante
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+VerifiedFindings.swift`
  - test `Tests/SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests.swift`
  - documentazione bug/changelog
- Non-scope:
  - refactor di `VerifiedFindingsService`
  - modifica del layer PostgreSQL/shared state
  - cambiamenti al contratto dei payload review oltre ai campi già esposti
- Moduli confinanti da verificare:
  - `TaskActivityStore`
  - `PipelineIntegrationService`
  - `VerifiedFindingsSessionSyncService`
- Test da aggiungere o aggiornare:
  - regressione che verifica la costruzione del payload con source `synced_from_snapshot` senza envelope embedded
  - regressione che preserva il source `embedded_snapshot` quando l’envelope è già nello snapshot
- Strategia di fix minimo:
  - usare `snapshot.verifiedFindings` o envelope già presente nello store in-memory
  - in assenza di envelope, usare `VerifiedFindingsSessionSyncService.sync(snapshot:)`
  - valutare replay/security gate tramite `VerifiedFindingsService.resolve(recovered:)`, evitando qualunque read da persistence
- Verifica post-fix:
  - payload review costruito senza passare da `MCPSharedState.readVerifiedFindingsEnvelope`
  - test mirati `PipelineIntegrationVerifiedFindingsTests`
- Commit previsto:
  - `fix(review): avoid blocking verified findings reads on review payload assembly`

## Evidenza raccolta
- Sample UI:
  - `/tmp/solo-code-main-57691-20260309-2216.sample.txt`
- Stack rilevante:
  ```text
  ChatPanelView.resolveRuntimeProvider
   -> TaskActivityStore.codeReviewPayload
   -> VerifiedFindingsService.resolve
   -> MCPSharedState.readVerifiedFindingsEnvelope
   -> PostgresPersistenceStore.ensureReady
   -> ManagedPostgresService.runProcess
   -> NSConcreteTask.waitUntilExit
  ```
