# P1 — La reserve FD del lock cross-process non viene ripristinata dopo il primo `EMFILE`

## Bug Fix Record
- Categoria: A
- Bug: il nuovo percorso `EMFILE/ENFILE` del lock advisory rilascia la reserve FD ma prova a ricrearla prima di chiudere il file descriptor del lock acquisito.
- Sintomo: il primo recovery da exhaustion può funzionare, ma i tentativi successivi restano senza reserve e possono terminare in `.fallback` / `fatalError`.
- Impatto: il path crash-safe del lock review/BugHunter smette di proteggere il processo proprio nel caso di saturazione FD che doveva gestire.
- Gravità: alta
- Steps to reproduce:
  1. Forzare `open(...)` del file lock a fallire con `EMFILE`.
  2. Usare la reserve FD per aprire con successo il `.lock`.
  3. Uscire dal body protetto.
  4. Verificare che la reserve non sia più disponibile al tentativo successivo.
- Risultato attuale: `replenishIfNeeded()` gira prima di `LOCK_UN` e `close(descriptor)`, quindi il processo è ancora al limite FD e la reserve non viene ricreata.
- Risultato atteso: la reserve deve essere ripristinata solo dopo unlock e close del file descriptor del lock.
- Causa probabile: ordine dei `defer` invertito nel ramo `.locked`.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CrossProcessLock.swift`
  - `Tests/CoderEngineTests/CodeReview/MCPSharedCodeReviewSnapshotStoreTests.swift`
- Non-scope:
  - redesign dell’API dei lock shared-state
  - modifiche al formato di persistenza snapshot
- Moduli confinanti da verificare:
  - `withCodeReviewFileLock(...)`
  - `withBugHunterAdvisoryLock(...)`
  - test lock cross-process review
- Test da aggiungere o aggiornare:
  - regressione che verifica il refill della reserve dopo un path `.locked(..., reserve)`
- Strategia di fix minimo:
  - consolidare unlock/close/replenish in un singolo teardown ordinato
- Verifica post-fix:
  - test mirato su `MCPSharedCodeReviewSnapshotStoreTests`
- Commit previsto: `fix(mcp-lock): restore reserve fd after advisory lock release`
