# Bug Fix Record
- Categoria: A - Critico
- Bug: i lock cross-process `CodeReviewLock` e `BugHunterLock` terminavano il processo con `fatalError` quando `open()` o `flock()` del file `.lock` fallivano
- Sintomo: crash dell'app durante code review o bughunter con stack su `withCodeReviewFileLock` o `withBugHunterFileLock`
- Impatto: il processo UI si chiudeva su errori recuperabili del filesystem o su saturazione dei file descriptor, interrompendo flussi core di review e persistence
- Gravità: P1
- Steps to reproduce:
  1. avviare `Solo Code` in una condizione con molti file descriptor aperti oppure con directory lock rimossa o assente
  2. aprire un flusso che legge o scrive shared state review o bughunter
  3. osservare il crash con `errno: 24` oppure `errno: 2`
- Risultato attuale: `open()` o `flock()` del file `.lock` falliscono e il processo entra in `fatalError`
- Risultato atteso: il lock deve degradare in modo sicuro, preservare la serializzazione intra-processo e non abbattere l'app
- Causa probabile: implementazione dei lock basata su `fatalError` per errori recuperabili del path `.lock`; inoltre `ENOENT` poteva presentarsi se la directory veniva ricreata fuori fase
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CrossProcessLock.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+BugHunterLock.swift`
  - `Tests/CoderEngineTests/CodeReview/MCPSharedCodeReviewSnapshotStoreTests.swift`
  - `Tests/SoloCodeAppTests/MCPSharedBugHunterFallbackLockTests.swift`
  - documentazione bug e changelog
- Non-scope:
  - refactor completo della persistence
  - redesign del contratto `MCPSharedState`
  - analisi strutturale completa del leak di pipe che porta a `EMFILE`
- Moduli confinanti da verificare:
  - `MCPSharedState+CodeReview.swift`
  - `MCPSharedState+VerifiedFindings.swift`
  - `MCPSharedState+BugHunterQueue.swift`
- Test da aggiungere o aggiornare:
  - regressione per fallback locale su errore `EMFILE`
  - regressione per fallback locale su errore `ENOENT`
  - regressione di serializzazione concorrente nel fallback
- Strategia di fix minimo:
  - introdurre un helper condiviso per lock advisory con retry su `ENOENT`
  - usare un fallback `NSRecursiveLock` locale al processo se il file lock non è ottenibile
  - mantenere invariati i path già corretti quando il file lock funziona regolarmente
- Verifica post-fix:
  - test mirati review e bughunter verdi
  - nessun `fatalError` nel path di lock su `EMFILE` e `ENOENT`
- Commit previsto:
  - `fix(mcp): make cross-process locks fail safe on lock errors`

## Evidenza raccolta
- Log utente:
  ```text
  CoderEngine/MCPSharedState+BugHunterLock.swift:24: Fatal error: BugHunterLock: impossibile aprire il file di lock ..., errno: 24
  CoderEngine/MCPSharedState+CrossProcessLock.swift:17: Fatal error: CodeReviewLock: impossibile aprire il file di lock ..., errno: 24
  ```
- Stack principale osservato:
  ```text
  ChatPanelView.resolveRuntimeProvider
   -> TaskActivityStore.ingestCodeReviewSnapshot
   -> CodeReviewSessionSnapshot.verifiedFindingsProjection
   -> VerifiedFindingsCheckpointService.resolveEnvelope
   -> MCPSharedState.readVerifiedFindingsEnvelope
   -> MCPSharedState.withCodeReviewFileLock
   -> _assertionFailure
  ```
