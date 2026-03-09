# 2026-03-09 — Cleanup descriptor e teardown sessioni MCP

## Obiettivo
Ridurre il rischio di saturazione dei file descriptor nel lifecycle MCP che portava a `errno: 24` sui lock cross-process review/BugHunter.

## Modifiche
- `MCPTransportFactory` ora chiude immediatamente le copie parent-side di stdin/stdout/stderr dopo `process.run()`
- `MCPTransportFactory` espone le risorse del trasporto da rilasciare esplicitamente in fase di teardown
- `MCPSessionManager` ora centralizza il teardown sessione:
  - `client.disconnect()`
  - chiusura descriptor del trasporto
  - terminazione del subprocess MCP
- aggiunto test di regressione che verifica il teardown del processo su `resetSession`

## File toccati
- `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPTransportFactory.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/MCPSessionManagerModels.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Lifecycle/MCPSessionManager+Lifecycle.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Utils/MCPSessionManager+Utils.swift`
- `Tests/CoderEngineTests/MCPSessionManagerTests.swift`
- `docs/bugs/P1-2026-03-09-mcp-transport-parent-pipes-not-released.md`

## Validazione
Eseguita con `xcodebuild` locale sul workspace:

```bash
xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' \
  -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/MCPSessionManagerTests/testResetSessionTerminatesSpawnedProcess
```

Esito:
- test eseguito con skip nel contesto corrente perché il binario `.build/coderide-mcp-server` non è presente
- build/test del perimetro completati senza failure

## Note
Questo intervento non prova a rifattorizzare tutti i `Process` runner dell’app. Si limita al lifecycle MCP che corrisponde ai sample e ai crash `EMFILE` raccolti.
