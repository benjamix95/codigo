# 2026-03-21 chat final root shell relocation

## Summary
- spostato fuori da `Chat` il guscio finale `ChatPanelView`
- spezzato il vecchio `PartA_UI` in file distinti per layout, lifecycle modifiers e panel resize
- spostato `PartE_TaskLifecycle` in `Services/ChatInteraction/ChatBindings`
- nessuna modifica di logica di produzione; solo relocation e split strutturale del shell Swift residuo

## Changes
- `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView.swift`
- `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+ShellProperties.swift`
- `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+RootLayout.swift`
- `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+LifecycleModifiers.swift`
- `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+PanelResize.swift`
- `App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+PartE_TaskLifecycle.swift`
- `App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+TaskLifecycleSupport.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati
  - aggiunti i nuovi file shell/lifecycle spezzati

## Validation
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat,App/SoloCodeApp/Sources/ChatView/Root,App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings,Solo Code.xcodeproj/project.pbxproj'`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPanelBuildBehaviorTests -only-testing:SoloCodeAppTests/ChatPanelScrollSafetyTests -only-testing:SoloCodeAppTests/ChatPanelPositionTests -only-testing:SoloCodeAppTests/ChatPanelTaskCompletionNotificationFlowTests -only-testing:SoloCodeAppTests/ChatBackgroundExecutionStateTests -only-testing:SoloCodeAppTests/ChatPanelFinalActionsVisibilityTests`
