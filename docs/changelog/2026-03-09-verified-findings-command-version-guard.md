# 2026-03-09 — VerifiedFindings command version guard

## Obiettivo
Far rispettare davvero `expectedEntityVersion` nel coordinatore dei comandi critici `VerifiedFindings`, senza introdurre nuova logica UI o cambiare i workflow applicativi già cablati.

## Modifiche
- aggiunto `VerifiedFindingsCommandError` con:
  - `versionUnavailable`
  - `versionConflict`
- esteso `VerifiedFindingsCommandCoordinator.execute` con provider opzionale `currentEntityVersion`
- introdotto il gate di optimistic concurrency:
  - se `expectedEntityVersion` è presente e la versione reale differisce, il comando fallisce
  - se manca una versione leggibile, il comando fallisce con errore esplicito
- mantenuta invariata la deduplica per `commandId` / fingerprint e la serializzazione per entity
- aggiunti test di regressione per:
  - duplicate command
  - version conflict
  - versione corretta

## File toccati
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCommandCoordinator.swift`
- `Tests/CoderEngineTests/VerifiedFindings/VerifiedFindingsCommandCoordinatorTests.swift`

## Validazione
Eseguita:

```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/VerifiedFindingsCommandCoordinatorTests \
  -only-testing:CoderEngineTests/CommandDeduplicationServiceTests
```

Esito:
- 4 test eseguiti
- 0 failure

## Note
Questo tranche non decide ancora come ogni workflow applicativo recupera la versione corrente dal canonical store, ma chiude il buco nel coordinatore shared e rende il contratto testabile.
