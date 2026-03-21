# 2026-03-21 chat send runtime bindings relocation

## Summary
- spostato il blocco `send-message / multi-turn runtime` fuori da `Chat`
- `PartL_SendMessage` e `PartL_SendMessageExecution` ora vivono in `Services/ChatSend/Runtime`
- `PartM_MultiTurn` ora vive in `Services/ChatPlan/Runtime`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro dei binding runtime

## Changes
- `App/SoloCodeApp/Sources/Services/ChatSend/Runtime/ChatPanelView+PartL_SendMessage.swift`
- `App/SoloCodeApp/Sources/Services/ChatSend/Runtime/ChatPanelView+PartL_SendMessageExecution.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_MultiTurn.swift`
- `Config/validation/rust-cutover-swift-allowlist.txt`
  - aggiunta la classificazione `Services/ChatSend/**`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ProviderFactoryCodeReviewTests -only-testing:SoloCodeAppTests/ChatPanelBuildBehaviorTests -only-testing:SoloCodeAppTests/PlanBuildIntegrationFlowTests -only-testing:SoloCodeAppTests/PlanShortcutAndCommandTests -only-testing:SoloCodeAppTests/PlanFlowPhaseTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartL_SendMessage.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartL_SendMessageExecution.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartM_MultiTurn.swift,App/SoloCodeApp/Sources/Services/ChatSend,App/SoloCodeApp/Sources/Services/ChatPlan/Runtime,Config/validation/rust-cutover-swift-allowlist.txt,Solo Code.xcodeproj/project.pbxproj'`
