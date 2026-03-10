# P1 — Restart/reconnect MCP possono sovrapporre due processi dello stesso server

## Bug Fix Record
- Categoria: A
- Bug: `restartServer` e `reconnect` rilanciavano il server senza aspettare la completa uscita del processo precedente.
- Sintomo: se il subprocess MCP ignora `SIGTERM` o chiude con ritardo, al ritorno del restart il vecchio PID può essere ancora vivo mentre il nuovo bootstrap è già partito.
- Impatto: rischio di processi orfani o duplicati che contendono lock, file del workspace o altre risorse condivise.
- Gravità: alta
- Steps to reproduce:
  1. Inserire una sessione MCP con un processo che ritarda l'uscita su `SIGTERM`.
  2. Chiamare `restartServer(...)` o `reconnect(...)`.
  3. Osservare che il restart ritorna prima della morte del vecchio PID.
- Risultato attuale: il restart poteva avviare la nuova sessione mentre il vecchio processo era ancora in chiusura.
- Risultato atteso: i restart espliciti devono attendere che il precedente processo sia terminato prima di avviare il nuovo bootstrap.
- Causa probabile: `disposeSession(..., waitForExit: false)` veniva usato anche nei path di restart esplicito.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Lifecycle/MCPSessionManager+Lifecycle.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Utils/MCPSessionManager+Teardown.swift`
  - `Tests/CoderEngineTests/MCPSessionManagerLifecycleRegressionTests.swift`
- Non-scope:
  - redesign del bootstrap MCP
  - cambi ai provider-side server
- Moduli confinanti da verificare:
  - `resetSession`
  - `restartServer`
  - `reconnect`
- Test da aggiungere o aggiornare:
  - regressione che verifica il wait del restart su un processo che esce in ritardo
- Strategia di fix minimo:
  - mantenere il cleanup non bloccante solo per stale session ed eviction
  - usare `waitForExit: true` nei restart/reconnect espliciti
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerLifecycleRegressionTests`
- Commit previsto: `fix(mcp): serialize teardown and wait explicit restart`
