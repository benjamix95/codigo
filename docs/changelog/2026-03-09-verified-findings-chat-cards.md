# 2026-03-09 — Verified Findings chat cards

## Cosa cambia
- aggiunto `VerifiedFindingsChatPresentationService` per generare card condivise finding/patch tra main chat e review panel chat
- il runtime main chat ora produce artifact `toolTrace` ricchi per i `reviewFinding`, con severity, domain, summary, verification e stato patch
- il review panel chat ora usa lo stesso presenter per i messaggi di `prepare/apply/revalidate/rollback/failure`, inclusa la patch preview diff
- estratti i blocchi review/diagnostics da `PipelineIntegrationService+EventSupport.swift` in file separati per mantenere il contenimento e i limiti dimensionali

## File principali
- `App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsChatPresentationService.swift`
- `App/SoloCodeApp/Sources/Runtime/PipelineIntegrationService+ReviewArtifacts.swift`
- `App/SoloCodeApp/Sources/Runtime/PipelineIntegrationService+Diagnostics.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Chat/ReviewPanelChatMessageFactory.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatMessages.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PatchWorkflow.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PatchWorkflow+Execution.swift`

## Test
- `SoloCodeAppTests/ReviewPanelChatMessageFactoryTests`
- `SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests`
- `SoloCodeAppTests/PipelineIntegrationLifecycleTests`
- `SoloCodeAppTests/ReviewPatchWorkflowServiceTests`

## Note
- nessuna modifica al core `VerifiedFindings`: il fix resta confinato al layer di presentazione chat e agli adapter runtime/panel
- `PipelineIntegrationService+EventSupport.swift` è stato riportato sotto soglia dimensionale estraendo review artifacts e diagnostics
