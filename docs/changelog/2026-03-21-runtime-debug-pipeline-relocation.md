# 2026-03-21 runtime debug pipeline relocation

## Summary
- spostati fuori da `Runtime` i servizi `DebugPipeline` che non appartengono al dominio runtime della main chat
- mantenuta invariata la logica; aggiornati solo percorsi, project file e allowlist

## Changes
- `App/SoloCodeApp/Sources/Services/DebugPipeline/ChatBindings/ChatPanelView+DebugPipelineIntents.swift`
- `App/SoloCodeApp/Sources/Services/DebugPipeline/ChatBindings/ChatPanelView+DebugPipelineNativeIntents.swift`
- `App/SoloCodeApp/Sources/Services/DebugPipeline/Native/DebugNativePipelineBackends.swift`
- `App/SoloCodeApp/Sources/Services/DebugPipeline/Native/DebugNativePipelineExecutor.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati
- `Config/validation/rust-cutover-swift-allowlist.txt`
  - aggiunta allowlist per `Services/DebugPipeline/**` come infrastruttura debug fuori dal dominio runtime main-chat

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/DebugStoreTests -only-testing:SoloCodeAppTests/DebugServiceFlowTests -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Runtime/DebugPipeline/ChatPanelView+DebugPipelineIntents.swift,App/SoloCodeApp/Sources/Runtime/DebugPipeline/ChatPanelView+DebugPipelineNativeIntents.swift,App/SoloCodeApp/Sources/Runtime/DebugPipeline/Native/DebugNativePipelineBackends.swift,App/SoloCodeApp/Sources/Runtime/DebugPipeline/Native/DebugNativePipelineExecutor.swift,App/SoloCodeApp/Sources/Services/DebugPipeline/ChatBindings/ChatPanelView+DebugPipelineIntents.swift,App/SoloCodeApp/Sources/Services/DebugPipeline/ChatBindings/ChatPanelView+DebugPipelineNativeIntents.swift,App/SoloCodeApp/Sources/Services/DebugPipeline/Native/DebugNativePipelineBackends.swift,App/SoloCodeApp/Sources/Services/DebugPipeline/Native/DebugNativePipelineExecutor.swift,Config/validation/rust-cutover-swift-allowlist.txt,Solo Code.xcodeproj/project.pbxproj'`
