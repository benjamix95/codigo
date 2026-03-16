# 2026-03-16 - Review batch 5 panel runtime views relocation

## Batch completato
- ricollocati sotto `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/`:
  - `CodeReviewPanelStore+ActionOutput.swift`
  - `CodeReviewPanelStore+ChatFindings.swift`
  - `CodeReviewPanelStore+ChatMessages.swift`
  - `CodeReviewPanelStore+CompletionFinalization.swift`
  - `CodeReviewPanelStore+LiveRunExecution.swift`

## Verifica eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests -only-testing:SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests -only-testing:SoloCodeAppTests/ReviewPanelChatStructuredContentTests`
- audit strict review-scope:
  - prima: `64` legacy non-UI
  - dopo: `59` legacy non-UI

## Note
- il batch drena altre 5 tranche senza cambiare il comportamento osservabile del panel
- il prefisso panel-side scende da `14` a `9`
