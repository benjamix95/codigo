# P1 — Code review UI ricade nel getter `verifiedFindingsProjection` che legge da shared state sotto lock sul main thread

## Categoria
Critico

## Bug
Il pannello code review e l'ingest delle snapshot usano ancora `CodeReviewSessionSnapshot.verifiedFindingsProjection` in alcuni path UI. Il getter ricostruisce `VerifiedFindings` tramite `VerifiedFindingsService.resolve(snapshot:)`, che passa da `MCPSharedState.readVerifiedFindingsEnvelope(sessionId:)` e quindi dal lock cross-process.

## Sintomo
- Freeze o crash della UI durante l'apertura/aggiornamento del pannello review.
- `fatalError` in `MCPSharedState.withCodeReviewFileLock` con `errno: 24`.
- Sample del main thread fermo su `TaskActivityStore.ingestCodeReviewSnapshot -> verifiedFindingsProjection -> readVerifiedFindingsEnvelope -> withCodeReviewFileLock`.

## Impatto
- Il pannello review smette di rispondere.
- La UI può andare in crash quando il processo ha già molti file descriptor aperti.
- Lo snapshot corrente può essere sovrascritto visivamente da uno stored envelope stantio.

## Causa probabile
Il fix precedente aveva rimosso la read bloccante dal payload review, ma erano rimasti call site nel layer app che usavano ancora il getter bridge `verifiedFindingsProjection` invece di derivare la projection da snapshot embedded o stato in-memory.

## Scope consentito
- `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+CodeReview.swift`
- `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+VerifiedFindings.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Chat/ReviewPanelChatMessageFactory.swift`
- test app review/verified findings

## Non-scope
- Contratto globale di `VerifiedFindingsService.resolve(snapshot:)`
- Persistence layer PostgreSQL
- Refactor dei lock cross-process

## Expected result
Il layer UI/review deve usare solo envelope embedded, cache in-memory o sync da snapshot corrente. Nessun path UI deve leggere `VerifiedFindings` da shared state/persistence sul main thread.

## Verifica
- Test di regressione con stored envelope confliggente: la UI deve preferire i finding dello snapshot corrente.
- Sample del freeze non deve più mostrare `verifiedFindingsProjection -> readVerifiedFindingsEnvelope` sul main thread.
