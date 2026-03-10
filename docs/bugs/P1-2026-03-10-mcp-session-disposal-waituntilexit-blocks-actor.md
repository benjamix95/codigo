# P1 — Teardown sessione MCP bloccava l'actor su `waitUntilExit()`

## Bug Fix Record
- Categoria: A
- Bug: `disposeSession(...)` attendeva l'uscita del subprocess per default, bloccando i path `resetSession`, `restartServer` e `shutdownAll`.
- Sintomo: un solo server MCP non cooperativo poteva congelare reconnect, retry e shutdown, perché l'actor `MCPSessionManager` restava occupato sul wait.
- Impatto: freeze del lifecycle MCP e serializzazione di tutte le altre richieste dietro un teardown bloccato.
- Gravità: alta
- Steps to reproduce:
  1. Inserire una sessione con subprocess che ignora `SIGTERM`.
  2. Invocare `resetSession(...)` o `restartServer(...)`.
  3. Misurare il tempo di ritorno del metodo.
- Risultato attuale: il metodo restituiva solo dopo l'uscita del processo.
- Risultato atteso: il teardown deve essere non bloccante per default e lasciare al processo la terminazione asincrona.
- Causa probabile: cambio del default `waitForExit` a `true` nel nuovo helper di disposal.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Utils/MCPSessionManager+Utils.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPTransportFactory.swift`
  - `Tests/CoderEngineTests/MCPSessionManagerTests.swift`
- Non-scope:
  - refactor del registry sessioni
  - gestione avanzata dei timeout di processo
- Moduli confinanti da verificare:
  - `MCPSessionManagerTests`
  - `MCPSessionManager+Lifecycle.swift`
- Test da aggiungere o aggiornare:
  - regressione su `resetSession(...)` che non deve attendere l'uscita del processo
- Strategia di fix minimo:
  - ripristinare il default non bloccante
  - centralizzare la terminazione processo in un helper riusabile
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests/testResetSessionDoesNotWaitForProcessExit`
- Commit previsto: `fix(mcp): keep session disposal nonblocking`

## Evidenza
- il nuovo test con processo che ignora `SIGTERM` verifica che `resetSession(...)` ritorni in meno di 500ms
- la sessione viene comunque rimossa dal manager e le risorse del trasporto vengono chiuse
