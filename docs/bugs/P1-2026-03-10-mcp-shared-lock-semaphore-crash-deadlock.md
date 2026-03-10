# P1 — Semaforo named del lock shared-state resta bloccato dopo un crash

## Bug Fix Record
- Categoria: A
- Bug: il lock cross-process introdotto con `sem_open(...)` non era crash-safe; se il processo moriva mentre deteneva il token, i caller successivi rimanevano bloccati indefinitamente.
- Sintomo: code review shared state e BugHunter potevano smettere di avanzare dopo un crash nel mezzo di una write protetta dal lock.
- Impatto: deadlock persistente del lifecycle MCP/shared-state fino a cleanup manuale.
- Gravità: alta
- Steps to reproduce:
  1. Entrare in `withCodeReviewFileLock(...)` o `withBugHunterFileLock(...)`.
  2. Terminare brutalmente il processo prima del `sem_post(...)`.
  3. Provare a riacquisire lo stesso lock.
- Risultato attuale: il semaforo named lasciava il contatore a `0` e il lock non tornava disponibile.
- Risultato atteso: il coordinamento cross-process deve essere crash-safe e auto-rilasciarsi alla morte del processo.
- Causa probabile: uso di un semaforo POSIX named al posto di un advisory file lock kernel-managed.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CrossProcessLock.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+EmergencyLockReserve.swift`
- Non-scope:
  - redesign completo della persistence shared-state
  - modifica dei call site MCPSharedState
- Moduli confinanti da verificare:
  - `MCPSharedState+BugHunterLock.swift`
  - `MCPSharedCodeReviewSnapshotStoreTests`
  - `MCPSharedBugHunter*Tests`
- Test da aggiungere o aggiornare:
  - regressioni su serializzazione del lock senza primitiva named persistente
- Strategia di fix minimo:
  - rimuovere il semaforo named dal path di produzione
  - recuperare i casi `EMFILE/ENFILE` tramite reserve FD, mantenendo `flock(...)`
- Verifica post-fix:
  - suite lock shared-state MCP/BugHunter
- Commit previsto: `fix(mcp): restore crash-safe shared lock acquisition`
