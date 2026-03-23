# 2026-03-09 — BugHunter autofix shared lifecycle queue

## Obiettivo
Portare anche il path applicativo di autofix `BugHunter` sul lifecycle service shared del core, eliminando l’enqueue manuale dei comandi review.

## Modifiche
- `BugHunterWorkflowService` ora espone `queueLifecycleCommand`
- `SoloCodeApp+BugHunterExecution+Autofix` usa il workflow service shared per prepare/apply/revalidate/rollback
- aggiunto test dedicato in `BugHunterWorkflowServiceTests`
- splittato il test `BugHunterAutofixFilterTests` per restare sotto soglia file

## File toccati
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/BugHunterWorkflowService.swift`
- `App/SoloCodeApp/Sources/App/Bootstrap/Sections/BugHunter/SoloCodeApp+BugHunterExecution+Autofix.swift`
- `Tests/CoderEngineTests/CodeReview/BugHunterAutofixFilterTests.swift`
- `Tests/CoderEngineTests/CodeReview/BugHunterWorkflowServiceTests.swift`
- `Solo Code.xcodeproj/project.pbxproj`

## Validazione
Eseguita con `xcodebuildmcp`:

```bash
xcodebuildmcp macos test --project-path 'Solo Code.xcodeproj' --scheme 'Solo Code-Debug' \
  --json '{"extraArgs":["-only-testing:CoderEngineTests/BugHunterAutofixFilterTests","-only-testing:CoderEngineTests/BugHunterWorkflowServiceTests","-only-testing:CoderEngineTests/BugHunterHandlerTests"]}'
```

Esito:
- 16 test eseguiti
- 0 failure
