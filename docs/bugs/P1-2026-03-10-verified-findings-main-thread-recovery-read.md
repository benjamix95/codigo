# P1 — Recovery persisted di verified findings nel path `@MainActor`

## Bug Fix Record
- Categoria: A
- Bug: il nuovo fallback di `verifiedFindingsEnvelope(...)` leggeva shared state e checkpoint sincronicamente dal path `ingestCodeReviewSnapshot(...)`, che gira su `@MainActor`.
- Sintomo: cold start del review panel o update live potevano tornare a bloccare la UI mentre tentavano recovery di envelope persistiti.
- Impatto: freeze/crash della UI review su percorso sensibile e hot.
- Gravità: alta
- Steps to reproduce:
  1. Iniettare uno snapshot review senza `verifiedFindings` embedded.
  2. Lasciare vuota la cache in-memory del `TaskActivityStore`.
  3. Aprire o aggiornare il review panel.
- Risultato attuale: il main actor poteva entrare in `MCPSharedState.readVerifiedFindingsEnvelope(...)` o `VerifiedFindingsCheckpointService.rebuildEnvelope(...)`.
- Risultato atteso: il path UI deve usare solo snapshot embedded o cache in-memory; eventuale recovery persistita va spostata fuori dal main actor.
- Causa probabile: estensione del fallback di `verifiedFindingsEnvelope(...)` a sorgenti persistite condivise.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+VerifiedFindings.swift`
  - `Tests/SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests.swift`
- Non-scope:
  - redesign del checkpoint service
  - recupero persistito asincrono completo
- Moduli confinanti da verificare:
  - `TaskActivityStore+CodeReview.swift`
  - payload verified findings nel review panel
- Test da aggiungere o aggiornare:
  - regressione sul cold-start che non legge envelope persistiti nel path sincrono UI
- Strategia di fix minimo:
  - limitare `verifiedFindingsEnvelope(...)` al solo stato in-memory nel path chiamato dal main actor
- Verifica post-fix:
  - `PipelineIntegrationVerifiedFindingsTests`
- Commit previsto: `fix(review): keep verified findings recovery off main actor`
