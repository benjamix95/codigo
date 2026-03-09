# 2026-03-09 — VerifiedFindings lifecycle command service

## Obiettivo
Centralizzare nel core shared la queue del lifecycle `review/security` per finding e patch, riducendo la logica duplicata negli handler MCP.

## Modifiche
- aggiunto `VerifiedFindingsLifecycleCommandService`
- `CodeReviewHandler+PatchWorkflow` ora usa il service condiviso per:
  - `verify_finding`
  - `prepare_patch`
  - `apply_patch`
  - `revalidate_finding`
  - `rollback_patch`
  - `close_finding`
- il service applica:
  - ownership validation
  - validazione session/conversation
  - gating su patch preparata e verificata per `apply_patch`
- mantenuti verdi i test su:
  - patch lifecycle handler
  - filtro autofix `BugHunter`

## File toccati
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsLifecycleCommandService.swift`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+PatchWorkflow.swift`
- `Tests/CoderEngineTests/CodeReview/BugHunterAutofixFilterTests.swift`
- `Solo Code.xcodeproj/project.pbxproj`

## Validazione
Eseguita con `xcodebuildmcp`:

```bash
xcodebuildmcp macos test --project-path 'Solo Code.xcodeproj' --scheme 'Solo Code-Debug' \
  --json '{"extraArgs":["-only-testing:CoderEngineTests/CodeReviewHandlerTests/testReviewRevalidateFindingQueuesCommand","-only-testing:CoderEngineTests/CodeReviewHandlerTests/testReviewRollbackPatchQueuesCommand","-only-testing:CoderEngineTests/CodeReviewHandlerTests/testReviewCloseFindingQueuesCommand","-only-testing:CoderEngineTests/BugHunterAutofixFilterTests"]}'
```

Esito:
- 14 test eseguiti
- 0 failure

## Note
Questo tranche non sostituisce ancora tutto il bus review con una command API completa del dominio, ma sposta un pezzo concreto del lifecycle sotto un service shared del core.
