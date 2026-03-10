# P1 — Teardown MCP reentrante con ownership non sicura dei file descriptor

## Bug Fix Record
- Categoria: A
- Bug: il lifecycle MCP non coordinava i teardown in-flight della stessa sessione, quindi richieste concorrenti potevano osservare il server come assente e avviare un nuovo bootstrap mentre il disconnect precedente era ancora sospeso.
- Sintomo: in presenza di `disconnect()` lenti o restart ravvicinati, potevano coesistere due lifecycle sullo stesso `serverId`.
- Impatto: rischio di doppio bootstrap, doppia chiusura delle risorse del trasporto e comportamento non deterministico nel lifecycle MCP.
- Gravità: alta
- Steps to reproduce:
  1. Inserire una sessione MCP nello store actor.
  2. Avviare un reset/restart mentre il teardown fa `await`.
  3. Emettere una seconda `session(for:)` o `tools(for:)` sullo stesso server prima che il disconnect finisca.
- Risultato attuale: il registry non esponeva uno stato di teardown in corso, quindi i call site concorrenti potevano partire come se non esistesse alcun teardown attivo.
- Risultato atteso: le richieste concorrenti devono attendere la fine del teardown in corso prima di ricreare o riutilizzare la sessione.
- Causa probabile: actor reentrancy durante `client.disconnect()` senza una barriera esplicita per `serverId`.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/MCPSessionManagerModels.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Utils/MCPSessionManager+Utils.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Lifecycle/MCPSessionManager+Lifecycle.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPTransportFactory.swift`
  - `Tests/CoderEngineTests/MCPSessionManagerTests.swift`
- Non-scope:
  - redesign del lifecycle MCP
  - modifica della policy `waitForExit`
- Moduli confinanti da verificare:
  - `MCPSessionManagerTests`
  - `MCPTransportFactory`
  - `restartServer` / `shutdownAll` / `evictIdleSessions`
- Test da aggiungere o aggiornare:
  - regressione su richieste concorrenti che attendono il teardown in-flight
- Strategia di fix minimo:
  - introdurre una barriera di teardown per `serverId`
  - fare attendere `session(for:)`, `resetSession`, `restartServer` ed eviction quando c'è un teardown attivo
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests`
- Commit previsto: `fix(mcp): guard session teardown ownership`

## Evidenza
- la regressione nuova verifica che `closeAll()` resti sicuro anche quando due copie di `MCPServerSession` condividono la stessa ownership del trasporto
