# P1 — Le stale session MCP lasciavano aperti i descriptor del trasporto

## Bug Fix Record
- Categoria: A
- Bug: quando `MCPSessionManager.session(for:)` trovava una sessione esistente con processo già terminato, rimuoveva la sessione senza eseguire il teardown completo delle `transportResources`.
- Sintomo: accumulo progressivo di `PIPE` nel processo UI fino a `EMFILE` (`errno: 24`), seguito da fallback rumoroso dei lock `CodeReviewLock`/`BugHunterLock` e fallimenti di scrittura su `MCPSharedState`.
- Impatto: freeze o degrado severo dopo ripetuti restart/discovery MCP; review/BugHunter non riescono più ad aprire lock file o salvare snapshot.
- Gravità: critica
- Steps to reproduce:
  1. Avviare Solo Code con server MCP che possono terminare o fallire durante la discovery.
  2. Forzare più cicli di `discoverAllTools`, reconnect o health checks.
  3. Osservare `lsof -p <pid>` crescere soprattutto su `PIPE`.
  4. Raggiunto il limite FD, osservare log `errno: 24` su lock cross-process e scritture MCP.
- Risultato attuale: le stale session non chiudono `input/output/stderr` del trasporto nel ramo di reconnessione implicita.
- Risultato atteso: ogni sessione stale deve essere smontata con lo stesso teardown usato da `resetSession`/`shutdownAll`, anche se il nuovo spawn fallisce subito.
- Causa probabile: nel ramo `existing.process.isRunning == false`, `session(for:)` chiamava solo `client.disconnect()` e `sessions.removeValue`, saltando `transportResources.closeAll()`.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Lifecycle/MCPSessionManager+Lifecycle.swift`
  - test `Tests/CoderEngineTests/MCPSessionManagerTests.swift`
- Non-scope:
  - refactor generale dei transport MCP
  - redesign del discovery flow
  - modifica della semantica dei lock `MCPSharedState`
- Moduli confinanti da verificare:
  - `MCPSessionManager+Utils`
  - `MCPTransportFactory`
  - `MCPSharedState+CrossProcessLock`
- Test da aggiungere o aggiornare:
  - regressione in `MCPSessionManagerTests.testSessionReconnectDisposesTransportResourcesForExitedSession()` che verifica la chiusura dei descriptor di una stale session anche quando la reconnessione fallisce
- Strategia di fix minimo:
  - riusare `disposeSession` nel ramo stale di `session(for:)`
  - verificare in test che i file descriptor risultino `EBADF` dopo la pulizia
- Verifica post-fix:
  - `xcodebuild build -project 'Solo Code.xcodeproj' -scheme CoderEngine -destination 'platform=macOS'`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests/testSessionReconnectDisposesTransportResourcesForExitedSession -only-testing:CoderEngineTests/MCPSharedCodeReviewSnapshotStoreTests`
- Commit previsto: `fix(mcp): dispose stale sessions before reconnect`

## Evidenza raccolta
- Processo app osservato con `lsof -n -p 97984 | wc -l`: circa `2046` FD aperti
- Distribuzione principale:
  - `1939 PIPE`
  - `103 REG`
- Log coerenti:
  - `CodeReviewLock ... errno: 24`
  - `BugHunterLock ... errno: 24`
  - `Failed to write code review snapshot ... sessions`
  - `Failed to write BugHunter hook events`
