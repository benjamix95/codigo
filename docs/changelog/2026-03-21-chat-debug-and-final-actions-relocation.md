# 2026-03-21 chat debug and final actions relocation

## Summary
- spostato il cluster `Debug` del `ChatPanelView` fuori da `Chat` in `Services/Debug/ChatBindings`
- spostata la barra `FinalChatActions` fuori da `Chat` in `ChatView/FinalActions`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro debug/UI e aggiornamento allowlist

## Changes
- `App/SoloCodeApp/Sources/Services/Debug/ChatBindings/ChatPanelView+PartG_AutoActivation.swift`
- `App/SoloCodeApp/Sources/Services/Debug/ChatBindings/ChatPanelView+PartG_DebugHandlers.swift`
- `App/SoloCodeApp/Sources/Services/Debug/ChatBindings/ChatPanelView+PartP_DebugProjectionBinding.swift`
- `App/SoloCodeApp/Sources/Services/Debug/ChatBindings/ChatPanelView+PartP_DebugRouting.swift`
- `App/SoloCodeApp/Sources/ChatView/FinalActions/ChatPanelView+PartD_FinalChatActions.swift`
- `Config/validation/rust-cutover-swift-allowlist.txt`
  - aggiunte le nuove classificazioni per `Services/Debug/ChatBindings/**` e `ChatView/FinalActions/ChatPanelView+PartD_FinalChatActions.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationDebugProjectionTests -only-testing:SoloCodeAppTests/DebugFlowToolE2ETests -only-testing:SoloCodeAppTests/DebugStoreTests -only-testing:SoloCodeAppTests/ChatPanelFinalActionsVisibilityTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Support/Extensions/Debug,App/SoloCodeApp/Sources/Chat/Support/Extensions/Messages/ChatPanelView+PartD_FinalChatActions.swift,App/SoloCodeApp/Sources/Services/Debug/ChatBindings,App/SoloCodeApp/Sources/ChatView/FinalActions/ChatPanelView+PartD_FinalChatActions.swift,Config/validation/rust-cutover-swift-allowlist.txt,Solo Code.xcodeproj/project.pbxproj'`
