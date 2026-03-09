# 2026-03-09 — Cleanup stale session MCP prima della reconnessione

## Obiettivo
Eliminare il leak di file descriptor che rimaneva quando una sessione MCP già morta veniva rimpiazzata senza teardown completo.

## Modifiche
- aggiornato `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Lifecycle/MCPSessionManager+Lifecycle.swift`
  - il ramo `existing.process.isRunning == false` ora usa `disposeSession(existing, waitForExit: false)` prima di rimuovere la sessione
  - questo garantisce la chiusura di `input`, `output` e `stderrReadHandle` del trasporto anche se il nuovo spawn fallisce immediatamente
- aggiornato `Tests/CoderEngineTests/MCPSessionManagerTests.swift`
  - aggiunge `testSessionReconnectDisposesTransportResourcesForExitedSession()`
  - crea una stale session con processo già uscito
  - forza una reconnessione verso un binario inesistente
  - verifica che i descriptor del vecchio trasporto risultino chiusi (`EBADF`) e che la sessione venga rimossa
  - rende il test indipendente dal testo localizzato dell'errore di spawn

## Validazione prevista
- `xcodebuild build -project 'Solo Code.xcodeproj' -scheme CoderEngine -destination 'platform=macOS'`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests/testSessionReconnectDisposesTransportResourcesForExitedSession -only-testing:CoderEngineTests/MCPSharedCodeReviewSnapshotStoreTests`

## Impatto atteso
- riduzione dell’accumulo di `PIPE` nel parent process
- meno probabilità di arrivare a `EMFILE`
- riduzione dei falsi problemi a cascata su `CodeReviewLock`, `BugHunterLock`, hook events e snapshot persistence
