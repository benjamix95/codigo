# 2026-03-21 chat timeline relocation

## Summary
- spostato il cluster `Timeline` da `Chat/Timeline` a `ChatView/Timeline`
- spostato `ChatPanelView+TodoCardSelection.swift` in `ChatView/Timeline/Support` per tenere la logica di visibilita' todo accanto alle card timeline
- spostato `ChatPanelView+TaskCompletionNotifications.swift` in `Services/TaskCompletionNotifications` per drenare un helper di supporto legacy dal prefisso `Chat`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro UI della timeline

## Changes
- `App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnView.swift`
- `App/SoloCodeApp/Sources/ChatView/Timeline/Blocks/ArtifactCardView.swift`
- `App/SoloCodeApp/Sources/ChatView/Timeline/Blocks/ChatTodoExecutionCardMetrics.swift`
- `App/SoloCodeApp/Sources/ChatView/Timeline/Blocks/ChatTodoExecutionCardView.swift`
- `App/SoloCodeApp/Sources/ChatView/Timeline/Blocks/TodoCenterCardView.swift`
- `App/SoloCodeApp/Sources/ChatView/Timeline/Support/ChatPanelView+TodoCardSelection.swift`
- `App/SoloCodeApp/Sources/Services/TaskCompletionNotifications/ChatPanelView+TaskCompletionNotifications.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path del cluster spostato

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTodoExecutionCardMetricsTests`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPanelTaskCompletionNotificationFlowTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Timeline,App/SoloCodeApp/Sources/Chat/Support/Extensions/UI/ChatPanelView+TodoCardSelection.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/Notifications/ChatPanelView+TaskCompletionNotifications.swift,App/SoloCodeApp/Sources/ChatView/Timeline,App/SoloCodeApp/Sources/Services/TaskCompletionNotifications/ChatPanelView+TaskCompletionNotifications.swift,Solo Code.xcodeproj/project.pbxproj'`
