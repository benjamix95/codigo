# Bug Fix Record
- Categoria: A - Critico
- Bug: crash di `Solo Code` durante il command loop BugHunter quando `withBugHunterFileLock` tenta di aprire `.lock`
- Sintomo: `fatalError` in `MCPSharedState+BugHunterLock.swift` con messaggio `impossibile aprire il file di lock`
- Impatto: crash del processo principale durante review/BugHunter; interruzione totale del workflow e perdita dello stato operativo in corso
- Gravità: P1
- Steps to reproduce:
  1. avviare `Solo Code`
  2. innescare review/BugHunter con subagent e MCP attivi
  3. lasciare accumulare runtime/subprocess multipli fino a saturare i descriptor
  4. osservare il crash quando il loop BugHunter prova a fare `claimPendingBugHunterCommands()`
- Risultato attuale: `open(.../.lock, O_RDWR|O_CREAT, 0644)` fallisce con `errno: 24` (`EMFILE`) e il processo va in crash
- Risultato atteso: i runtime MCP devono riusare la stessa sessione/shared manager, evitando proliferazione di subprocess e saturazione di pipe/file descriptor
- Causa probabile: i `UnifiedToolRuntime` creati col default costruiscono ciascuno un nuovo `MCPSessionManager()`, che a sua volta apre nuove sessioni MCP e nuovi `coderide-mcp-server`; il processo accumula pipe fino a esaurire i file descriptor disponibili
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/MCPSessionManager.swift`
  - `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Core/Execution/Runtime/Contracts/UnifiedToolRuntime+RuntimeContracts.swift`
  - test runtime/MCP associati
- Non-scope:
  - refactor del BugHunter command loop
  - modifica della semantica del file lock
  - riarchitettura completa dei process runner
- Moduli confinanti da verificare:
  - `UnifiedToolRuntime`
  - `MCPSessionManager`
  - `ProviderFactory.buildRuntime`
  - esecuzione subagent MCP
- Test da aggiungere o aggiornare:
  - regressione che verifica che due `UnifiedToolRuntime()` di default riusino lo stesso `MCPSessionManager.shared`
- Strategia di fix minimo:
  - introdurre singleton engine-level `MCPSessionManager.shared`
  - usare quel singleton come default del costruttore `UnifiedToolRuntime`
- Verifica post-fix:
  - test di regressione runtime/MCP
  - build/test mirati dell’area runtime/session manager
  - conferma diagnostica: il crash osservato prima era associato a `errno: 24` e a decine di `coderide-mcp-server`
- Commit previsto:
  - `fix(mcp): reuse shared session manager for default runtimes`

## Evidenza raccolta
- PID analizzato: `68106` (`Solo Code`)
- Sample: `/tmp/solo-code-68106.sample.txt`
- Log crash:
  - `2026-03-09 21:04:45.090 ... Fatal error: BugHunterLock: impossibile aprire il file di lock ... errno: 24`
- Stato processo al momento dell’analisi:
  - `open_fd_count=2665`
  - `2544 PIPE`
  - `21` processi `coderide-mcp-server --workspace .`

## Note
- Il file `.lock` e la directory `bughunter` esistono e sono regolari; il problema non è di path o permessi ma di esaurimento descriptor.
