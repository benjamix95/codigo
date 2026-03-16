# 2026-03-16 - Review panel app-side zero

## Tranche completata
- ricollocati sotto `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/`:
  - `CodeReviewPanelStore.swift`
  - `CodeReviewPanelStore+SnapshotMutation.swift`

## Verifica eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelStoreRestoresCachedChatSessionState -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testStructuredChatFindingsSyncsIntoFindingsTimelineAndDeduplicates -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests`
- audit strict review-scope:
  - prima: `49` legacy non-UI
  - dopo: `47` legacy non-UI

## Note
- il lato app/panel review e' ora completamente drenato dal backlog non-UI
- il debito residuo review e' rimasto solo in `Engine/CoderEngine/Sources/CodeReview`, `Engine/CoderEngine/Sources/VerifiedFindingsCore` e `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview`
