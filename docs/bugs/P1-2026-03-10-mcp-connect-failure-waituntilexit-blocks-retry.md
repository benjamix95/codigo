# P1 — Cleanup di connect MCP fallito bloccava retry e health check

## Bug Fix Record
- Categoria: A
- Bug: il cleanup del path `transport.connect()` fallito attendeva `process.waitUntilExit()`, trasformando un errore di connessione recuperabile in un possibile blocco indefinito.
- Sintomo: `session(for:)`, `listTools` e gli health check potevano restare appesi quando il subprocess MCP partiva ma non completava il protocollo o ignorava `SIGTERM`.
- Impatto: freeze del lifecycle MCP, retry non completati, health check bloccati e perdita di recuperabilità automatica.
- Gravità: alta
- Steps to reproduce:
  1. Avviare un processo MCP che resta vivo ma non parla correttamente il protocollo.
  2. Forzare un failure nel path `transport.connect()`.
  3. Osservare il caller che attende il cleanup.
- Risultato attuale: il caller rimaneva in attesa dell'uscita del processo prima di ricevere l'errore.
- Risultato atteso: il cleanup deve terminare il processo e rilasciare le risorse senza bloccare il thread chiamante.
- Causa probabile: l'introduzione di `waitUntilExit()` nel catch di `connectToProcess(...)`.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPTransportFactory.swift`
  - `Tests/CoderEngineTests/MCPSessionManagerTests.swift`
- Non-scope:
  - refactor del client MCP
  - redesign del retry policy
- Moduli confinanti da verificare:
  - `MCPSessionManagerTests`
  - call path `health`, `listTools`, `session(for:)`
- Test da aggiungere o aggiornare:
  - regressione su cleanup fallito che non attende la terminazione del processo
- Strategia di fix minimo:
  - estrarre un helper di cleanup non bloccante per i failure di connessione
  - mantenere invariato il rilascio dei descriptor
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests/testCleanupFailedConnectionDoesNotWaitForProcessExit`
- Commit previsto: `fix(mcp): avoid blocking teardown on failed transport connect`

## Evidenza
- il nuovo test usa un processo che ignora `SIGTERM` e verifica che il cleanup ritorni subito
- i descriptor del trasporto vengono comunque chiusi nel path di errore
