# P1 — Teardown MCP reentrante con ownership non sicura dei file descriptor

## Bug Fix Record
- Categoria: A
- Bug: `resetSession` / `restartServer` / eviction potevano lasciare la stessa sessione MCP visibile nell'actor mentre il teardown era già in corso.
- Sintomo: in presenza di chiamate ravvicinate sullo stesso server, due path potevano chiudere gli stessi file descriptor su copie diverse della sessione.
- Impatto: rischio di chiusura doppia dei descriptor del trasporto e comportamento non deterministico nel lifecycle MCP.
- Gravità: alta
- Steps to reproduce:
  1. Inserire una sessione MCP nello store actor.
  2. Avviare un reset/restart mentre il teardown fa `await`.
  3. Rientrare nell'actor con un secondo teardown sulla stessa sessione.
- Risultato attuale: la sessione restava nel dizionario fino a dopo l'`await`, quindi la stessa ownership poteva essere osservata due volte.
- Risultato atteso: la sessione deve essere rimossa dal registry prima di qualunque `await`, e le risorse del trasporto devono chiudersi in modo idempotente.
- Causa probabile: actor reentrancy durante `client.disconnect()` combinata con `MCPTransportResources` value-type non condiviso.
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
  - regressione su `MCPTransportResources.closeAll()` idempotente anche su copie di sessione
- Strategia di fix minimo:
  - rimuovere la sessione dal dizionario prima del teardown asincrono
  - trasformare `MCPTransportResources` in ownership condivisa e idempotente
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests`
- Commit previsto: `fix(mcp): guard session teardown ownership`

## Evidenza
- la regressione nuova verifica che `closeAll()` resti sicuro anche quando due copie di `MCPServerSession` condividono la stessa ownership del trasporto
