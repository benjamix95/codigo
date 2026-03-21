# 2026-03-21 chat task activity bindings relocation

## Summary
- spostato il cluster task activity/execution bindings fuori da `Chat` in `Services/ChatInteraction/ChatBindings`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro dei binding UI/runtime del pannello chat

## Changes
- `App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+PartH_TaskActivity.swift`
- `App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+PartE_ExecutionControl.swift`
- `App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+DisplayFlags.swift`
- `App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+PartA_NotificationModifiers.swift`
- `Config/validation/rust-cutover-swift-allowlist.txt`
  - aggiunta la classificazione `Services/ChatInteraction/**`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatBackgroundExecutionStateTests -only-testing:SoloCodeAppTests/ComposerRuntimeTimerTests -only-testing:SoloCodeAppTests/TaskActivityVisibilityTests -only-testing:SoloCodeAppTests/TaskActivityStoreInstantGrepTests -only-testing:SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests -only-testing:SoloCodeAppTests/ExecutionControllerPauseResumeTests -only-testing:SoloCodeAppTests/TaskActivityPanelScopingTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Support/Extensions/ComposerUI/ChatPanelView+PartH_TaskActivity.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/Lifecycle/ChatPanelView+PartE_ExecutionControl.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/UI/ChatPanelView+DisplayFlags.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/UI/ChatPanelView+PartA_NotificationModifiers.swift,App/SoloCodeApp/Sources/Services/ChatInteraction,Config/validation/rust-cutover-swift-allowlist.txt,Solo Code.xcodeproj/project.pbxproj'`
