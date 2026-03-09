# 2026-03-09 — Shared patch execution service

## Obiettivo
Eliminare la duplicazione residua dell’orchestrazione patch tra panel store e command loop dell’app, riusando un service app-level condiviso sopra `ReviewPatchWorkflowService`.

## Modifiche
- aggiunto `VerifiedFindingsPatchExecutionService`
- `CodigoApp+CodeReviewPatchCommands` ora usa il service condiviso per il lifecycle patch
- `CodeReviewPanelStore+PatchWorkflow` ora usa lo stesso service condiviso
- splittato `CodeReviewPanelStore+PatchWorkflow` con file di supporto:
  - `CodeReviewPanelStore+PatchWorkflow+Execution.swift`
- aggiunto test di regressione nel file `ReviewPatchWorkflowServiceTests`

## File toccati
- `App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift`
- `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/CodigoApp+CodeReviewPatchCommands.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PatchWorkflow.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PatchWorkflow+Execution.swift`
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`
- `Solo Code.xcodeproj/project.pbxproj`

## Validazione
Eseguita con `xcodebuildmcp`:

```bash
xcodebuildmcp macos test --project-path 'Solo Code.xcodeproj' --scheme 'Solo Code-Debug' \
  --json '{"extraArgs":["-only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests","-only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests","-only-testing:CoderEngineTests/CodeReviewHandlerTests"]}'
```

Esito:
- 48 test eseguiti
- 0 failure
