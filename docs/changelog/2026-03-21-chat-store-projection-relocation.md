# 2026-03-21 chat store projection relocation

## Summary
- spostato il cluster `StoreProjection` da `Chat/Support` a `Services/ChatStore`
- spostato `ChatPanelSupport+Core` da `Chat/Support` a `Services/ChatThread`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro dell’infrastruttura di store/persistenza e dei support helpers della chat

## Changes
- `App/SoloCodeApp/Sources/Services/ChatStore/Checkpoints/*`
- `App/SoloCodeApp/Sources/Services/ChatStore/Conversations/*`
- `App/SoloCodeApp/Sources/Services/ChatStore/Core/*`
- `App/SoloCodeApp/Sources/Services/ChatStore/Models/*`
- `App/SoloCodeApp/Sources/Services/ChatStore/Persistence/*`
- `App/SoloCodeApp/Sources/Services/ChatStore/Plans/*`
- `App/SoloCodeApp/Sources/Services/ChatStore/Summary/*`
- `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path del cluster spostato

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreTaskOwnershipTests`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStorePlansMutationTests`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreCheckpointTests`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreMigrationTests`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/RustMainChatAutoTodoBoundaryTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Support/StoreProjection,App/SoloCodeApp/Sources/Chat/Support/ChatPanelSupport+Core.swift,App/SoloCodeApp/Sources/Services/ChatStore,App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift,Solo Code.xcodeproj/project.pbxproj'`
