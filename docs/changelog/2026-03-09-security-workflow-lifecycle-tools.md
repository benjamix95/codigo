# 2026-03-09 — Security workflow lifecycle tools

## Obiettivo
Completare il wrapper MCP `Security` sopra il backend shared `Review/VerifiedFindings`, evitando logica duplicata e chiudendo il compile break introdotto dal nuovo handler.

## Modifiche
- corretto `SecurityHandler+Routing` per usare valori stringa canonici invece di enum non visibili nel target MCP
- registrati i tool `Security` nel catalogo globale `CoderIDETools.all`
- estesa la surface `security_*` con adapter sottili per:
  - `security_verify_finding`
  - `security_preview_patch`
  - `security_verify_patch`
  - `security_revalidate_finding`
  - `security_rollback_patch`
  - `security_close_finding`
- aggiornato `IDEStateTools` per instradare i nuovi tool `security_*`
- rimosso il dispatch duplicato di `close_finding` dal command loop review
- aggiunti test di regressione per il routing `Security` verso il workflow shared

## File toccati
- `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodigoApp+CodeReviewCommands.swift`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CoderIDEMCPServerApp+IDEStateTools.swift`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security/SecurityHandler.swift`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security/SecurityHandler+Routing.swift`
- `Tools/CoderIDEMCPServer/Sources/Tools/Catalog/CoderIDETools.swift`
- `Tools/CoderIDEMCPServer/Sources/Tools/Catalog/CoderIDETools+SecurityWorkflow.swift`
- `Tests/CoderEngineTests/Security/SecurityHandlerTests.swift`

## Validazione
Eseguita:

```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/SecurityHandlerTests \
  -only-testing:CoderEngineTests/CodeReviewHandlerTests/testReviewCloseFindingQueuesCommand
```

Esito:
- 5 test eseguiti
- 0 failure

## Note
Il wrapper `Security` resta un adapter del workflow review shared: nessuna state machine locale, nessuna logica alternativa nel panel o nella chat.
