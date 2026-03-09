# Bug Fix Record
- Categoria: A - Critico
- Bug: le sessioni MCP lasciavano aperti descriptor/pipe del parent process e non ripulivano in modo forte le risorse del trasporto al reset/shutdown
- Sintomo: accumulo di `PIPE` nel processo UI fino a `errno: 24` (`EMFILE`) e crash/fatal error durante `withCodeReviewFileLock` o `withBugHunterFileLock`
- Impatto: crash o freeze dell’app durante review/BugHunter, impossibilità di aprire i lock file cross-process e degrado progressivo della stabilità runtime
- Gravità: P1
- Steps to reproduce:
  1. avviare `Solo Code`
  2. usare ripetutamente funzioni review/MCP o lasciare attivi loop MCP/health checks
  3. osservare l’aumento dei descriptor con `lsof -p <pid>`
  4. quando il processo raggiunge migliaia di `PIPE`, i lock MCP falliscono con `errno: 24`
- Risultato attuale: `MCPTransportFactory.connectToProcess` e il teardown di `MCPSessionManager` non rilasciano sempre tutte le handle del parent, e i session reset non chiudono esplicitamente input/output/stderr del trasporto
- Risultato atteso: dopo spawn e dopo teardown, il parent deve mantenere solo le handle strettamente necessarie; reset/shutdown devono chiudere le risorse del trasporto e terminare il processo figlio
- Causa probabile: le copie parent-side di stdin/stdout/stderr del subprocess e i descriptor usati da `StdioTransport` restavano aperti oltre il necessario; `resetSession`/`shutdownAll` terminavano il process senza chiudere in modo centralizzato tali risorse
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPTransportFactory.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/MCPSessionManagerModels.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Lifecycle/MCPSessionManager+Lifecycle.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Utils/MCPSessionManager+Utils.swift`
  - test `Tests/CoderEngineTests/MCPSessionManagerTests.swift`
  - documentazione bug/changelog
- Non-scope:
  - redesign del protocollo MCP
  - refactor globale di tutti i `Process` runner dell’app
  - modifiche semantiche ai file lock review/BugHunter
- Moduli confinanti da verificare:
  - `MCPSessionManager`
  - `MCPTransportFactory`
  - `UnifiedToolRuntime` lato MCP
  - `MCPSharedState+CrossProcessLock`
- Test da aggiungere o aggiornare:
  - regressione che verifica che `resetSession` termini il subprocess MCP spawnato
- Strategia di fix minimo:
  - chiudere subito le copie parent-side di stdin/stdout/stderr dopo `process.run()`
  - tracciare le risorse del trasporto nella sessione MCP
  - centralizzare il teardown con chiusura di descriptor + `client.disconnect()` + `process.terminate()`
- Verifica post-fix:
  - test mirato `MCPSessionManagerTests/testResetSessionTerminatesSpawnedProcess`
  - assenza di nuovi errori `disposeSession`/cleanup in build
- Commit previsto:
  - `fix(mcp): release transport descriptors during session teardown`

## Evidenza raccolta
- `lsof -p 57691 | wc -l`:
  - `2657`
- Top tipi FD:
  - `2544 PIPE`
- Log crash:
  ```text
  Fatal error: BugHunterLock: impossibile aprire il file di lock ... errno: 24
  Fatal error: CodeReviewLock: impossibile aprire il file di lock ... errno: 24
  ```
