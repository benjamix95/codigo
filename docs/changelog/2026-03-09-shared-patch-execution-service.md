# 2026-03-09 — Shared patch execution service

## Obiettivo
Eliminare l’ultima duplicazione sostanziale dell’orchestrazione patch tra panel store e command loop dell’app, riusando un service condiviso sopra `ReviewPatchWorkflowService`.

## Modifiche
- aggiunto `VerifiedFindingsPatchExecutionService`
- `SoloCodeApp+CodeReviewPatchCommands` ora usa il service condiviso
- `CodeReviewPanelStore+PatchWorkflow` ora usa lo stesso service condiviso
- spezzato `CodeReviewPanelStore+PatchWorkflow` con file di supporto:
  - `CodeReviewPanelStore+PatchWorkflow+Execution.swift`
- aggiunto test di regressione sul mapping snapshot/patch in `ReviewPatchWorkflowServiceTests`

## File toccati
- `App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift`
- `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/SoloCodeApp+CodeReviewPatchCommands.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PatchWorkflow.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PatchWorkflow+Execution.swift`
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`
- `Solo Code.xcodeproj/project.pbxproj`

## Validazione
Eseguita con `xcodebuildmcp`:

```bash
xcodebuildmcp macos test --project-path 'Solo Code.xcodeproj' --scheme 'Solo Code-Debug' \
  --json '{"extraArgs":["-only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests","-only-testing:CoderEngineTests/VerifiedFindingsQueryServiceTests","-only-testing:CoderEngineTests/VerifiedFindingsStatusServiceTests","-only-testing:CoderEngineTests/VerifiedFindingsServiceTests","-only-testing:CoderEngineTests/VerifiedFindingsReplayServiceTests","-only-testing:CoderEngineTests/VerifiedFindingsSharedStateTests","-only-testing:CoderEngineTests/VerifiedFindingsSessionSyncServiceTests","-only-testing:CoderEngineTests/VerifiedFindingsCommandCoordinatorTests","-only-testing:CoderEngineTests/VerifiedFindingsSecurityGateServiceTests","-only-testing:CoderEngineTests/CodeReviewHandlerTests","-only-testing:CoderEngineTests/SecurityHandlerTests","-only-testing:CoderEngineTests/BugHunterHandlerTests","-only-testing:CoderEngineTests/BugHunterAutofixFilterTests","-only-testing:CoderEngineTests/BugHunterWorkflowServiceTests","-only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests","-only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests","-only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests"]}'
```

Esito:
- 96 test eseguiti
- 0 failure
