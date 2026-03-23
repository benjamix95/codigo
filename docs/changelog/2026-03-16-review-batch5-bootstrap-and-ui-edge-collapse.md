# 2026-03-16 - Review batch 5 bootstrap and UI-edge collapse

## Batch completato
- assorbiti in `ReviewCommandRustBridge.swift`:
  - `CodeReviewCommandLoopDriver.swift`
  - `CodeReviewCommandRuntimeHooks.swift`
  - `SoloCodeApp+CodeReviewCommandConfigure.swift`
- ricollocati sotto `Views/**`:
  - `ReviewPanelCoordinator.swift`
  - `ReviewPanelChatSessionStore.swift`

## Verifica eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests -only-testing:SoloCodeAppTests/ReviewPanelChatStructuredContentTests`
- audit strict review-scope:
  - prima: `69` legacy non-UI
  - dopo: `64` legacy non-UI

## Note
- il batch ha drenato 5 tranche in un solo passaggio senza introdurre nuovi file Swift non-UI
- il bootstrap review app-side scende da `6` a `3` file legacy
- il panel app-side scende da `16` a `14` file legacy
