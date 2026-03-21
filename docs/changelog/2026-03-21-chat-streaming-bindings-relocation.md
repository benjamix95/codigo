# 2026-03-21 chat streaming bindings relocation

## Summary
- spostato il cluster `streaming/finalization` fuori da `Chat` in `Services/ChatStreaming/Bindings`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro dei binding streaming della chat

## Changes
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartE_ToolTraceTurn.swift`
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartO_Streaming1.swift`
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_Streaming2.swift`
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartQ_Finalizers.swift`
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_PolicyEnforcement.swift`
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartR_Rewind.swift`
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartR_StreamErrors.swift`
- `Config/validation/rust-cutover-swift-allowlist.txt`
  - aggiunta la classificazione `Services/ChatStreaming/**`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStreamFailureHandlingTests -only-testing:SoloCodeAppTests/ChatPanelTodoFinalizationTests -only-testing:SoloCodeAppTests/ChatPanelReasoningMergeTests -only-testing:SoloCodeAppTests/ChatPanelTraceBindingTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/RustMainChatProviderAdapterTests -only-testing:SoloCodeAppTests/ChatStoreStreamingTargetTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Support/Extensions/Lifecycle/ChatPanelView+PartE_ToolTraceTurn.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartO_Streaming1.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartP_Streaming2.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartQ_Finalizers.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/Streaming/ChatPanelView+PartP_PolicyEnforcement.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/Streaming/ChatPanelView+PartR_Rewind.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/Streaming/ChatPanelView+PartR_StreamErrors.swift,App/SoloCodeApp/Sources/Services/ChatStreaming,Config/validation/rust-cutover-swift-allowlist.txt,Solo Code.xcodeproj/project.pbxproj'`
