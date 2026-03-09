# 2026-03-09 — BugHunter autofix selection on VerifiedFindings

## Obiettivo
Portare anche la scelta del finding `autofix` di `BugHunter` sul backend shared `VerifiedFindings`, invece di lasciarla ancorata al modello review raw.

## Modifiche
- aggiunto `BugHunterAutofixSelectionService`
- `CodigoApp+BugHunterExecution+Autofix` ora:
  - risolve lo stato shared via `VerifiedFindingsService`
  - seleziona il finding autofixable dal canonical snapshot
  - continua a usare il workflow review shared per prepare/apply/revalidate/rollback
- aggiunto test di regressione sul filtro canonico in `BugHunterAutofixFilterTests`
- mantenuti i test MCP/app su `BugHunter` e pipeline integration

## File toccati
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/BugHunterAutofixSelectionService.swift`
- `App/SoloCodeApp/Sources/App/Bootstrap/Sections/BugHunter/CodigoApp+BugHunterExecution+Autofix.swift`
- `Tests/CoderEngineTests/CodeReview/BugHunterAutofixFilterTests.swift`
- `Solo Code.xcodeproj/project.pbxproj`

## Validazione
Eseguita con `xcodebuildmcp`:

```bash
xcodebuildmcp macos test --project-path 'Solo Code.xcodeproj' --scheme 'Solo Code-Debug' \
  --json '{"extraArgs":["-only-testing:CoderEngineTests/BugHunterAutofixFilterTests","-only-testing:CoderEngineTests/BugHunterHandlerTests","-only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests"]}'
```

Esito:
- 15 test eseguiti
- 0 failure

## Note
Questo tranche non elimina ancora il workflow review dal backend `BugHunter`, ma sposta una decisione chiave sul canonical shared state, che è il passo corretto per chiudere la biforcazione residua.
