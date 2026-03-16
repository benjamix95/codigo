# 2026-03-16 - Review batch 5 bootstrap residuals drained

## Batch completato
- spostato `ReviewCommandRustBridge.swift` in `App/SoloCodeApp/Sources/CodeReview/Services/`
- assorbiti i residuali bootstrap:
  - `CodigoApp+CodeReviewDeferredCommands.swift`
  - `CodigoApp+CodeReviewPatchCommands.swift`
- ricollocati sotto `Views/Runtime/`:
  - `CodeReviewPanelStore+TargetedFix.swift`
  - `CodeReviewPanelStore+PatchWorkflow+Execution.swift`

## Verifica eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelTargetedFixLaunchUsesRustPlannerWithSourcePrefixAndConfig`
- audit strict review-scope:
  - prima: `54` legacy non-UI
  - dopo: `49` legacy non-UI

## Note
- bootstrap review app-side e' ora a `0`
- il panel-side scende da `4` a `2`
