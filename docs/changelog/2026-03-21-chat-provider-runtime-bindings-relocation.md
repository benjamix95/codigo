# 2026-03-21 chat provider runtime bindings relocation

## Summary
- spostato il cluster `provider/runtime policy` fuori da `Chat` in `Services/ChatProviders/Bindings`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro dei binding provider della chat

## Changes
- `App/SoloCodeApp/Sources/Services/ChatProviders/Bindings/ChatPanelView+PartI_ProviderSync.swift`
- `App/SoloCodeApp/Sources/Services/ChatProviders/Bindings/ChatPanelView+PartI_RuntimeHelpers.swift`
- `App/SoloCodeApp/Sources/Services/ChatProviders/Bindings/ChatPanelView+PartI_ToolRuntimePolicy.swift`
- `Config/validation/rust-cutover-swift-allowlist.txt`
  - aggiunta la classificazione `Services/ChatProviders/**`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ThreadProviderSelectionServiceTests -only-testing:SoloCodeAppTests/ProviderFactoryClaudeAllowedToolsTests -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/PlanShortcutAndCommandTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartI_ProviderSync.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/Providers/ChatPanelView+PartI_RuntimeHelpers.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/Providers/ChatPanelView+PartI_ToolRuntimePolicy.swift,App/SoloCodeApp/Sources/Services/ChatProviders,Config/validation/rust-cutover-swift-allowlist.txt,Solo Code.xcodeproj/project.pbxproj'`
