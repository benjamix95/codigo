# 2026-03-21 chat thread shell bindings relocation

## Summary
- spostato il cluster `thread/message shell` fuori da `Chat` in `Services/ChatThread/Bindings`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro dei binding del thread chat

## Changes
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageHeader.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageScrollState.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartD_MessagesScroll.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartR_Tail.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartS_End.swift`
- `Config/validation/rust-cutover-swift-allowlist.txt`
  - aggiunta la classificazione `Services/ChatThread/Bindings/**`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPanelScrollSafetyTests -only-testing:SoloCodeAppTests/ChatPanelPositionTests -only-testing:SoloCodeAppTests/ChatPanelReasoningMergeTests -only-testing:SoloCodeAppTests/ChatPanelTraceBindingTests -only-testing:SoloCodeAppTests/TaskActivityVisibilityTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartC_MessageHeader.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartC_MessageScrollState.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartD_MessagesScroll.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartR_Tail.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartS_End.swift,App/SoloCodeApp/Sources/Services/ChatThread/Bindings,Config/validation/rust-cutover-swift-allowlist.txt,Solo Code.xcodeproj/project.pbxproj'`
