# P2 — Il default reserve di `withAdvisoryFileLock(...)` apre un FD che può perdere

## Bug Fix Record
- Categoria: B
- Bug: il default argument di `withAdvisoryFileLock(...)` istanzia sempre una nuova `EmergencyLockDescriptorReserve`, che apre `/dev/null` in `init`.
- Sintomo: i caller che non passano una reserve esplicita accumulano un file descriptor per invocazione.
- Impatto: il helper può reintrodurre pressione su FD, specialmente nei test diretti o in futuri call site generici.
- Gravità: media
- Steps to reproduce:
  1. Invocare `withAdvisoryFileLock(...)` più volte senza passare `emergencyReserve`.
  2. Misurare il numero di file descriptor aperti del processo.
- Risultato attuale: il conteggio cresce perché la reserve implicita apre un FD non necessario nel path di default.
- Risultato atteso: il path di default non deve allocare alcuna reserve, oppure deve chiuderla deterministicamente.
- Causa probabile: default argument con side effect (`EmergencyLockDescriptorReserve()`) sul wrapper generico.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CrossProcessLock.swift`
  - `Tests/CoderEngineTests/CodeReview/MCPSharedCodeReviewSnapshotStoreTests.swift`
- Non-scope:
  - refactor dei test review snapshot
  - modifiche ai wrapper call-site già dotati di reserve statica
- Moduli confinanti da verificare:
  - helper `withAdvisoryFileLock(...)`
  - test che usano il fallback diretto con `acquireLock`
- Test da aggiungere o aggiornare:
  - regressione sul numero di FD aperti per il path default
- Strategia di fix minimo:
  - rendere opzionale la reserve generica e mantenerla solo nei wrapper review/BugHunter che la usano davvero
- Verifica post-fix:
  - test mirato su `MCPSharedCodeReviewSnapshotStoreTests`
- Commit previsto: `fix(mcp-lock): avoid implicit reserve fd allocation`
