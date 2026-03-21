# 2026-03-21 chat composer bindings relocation

## Summary
- spostato il blocco `ComposerUI` e sidebar bindings fuori da `Chat` in `Services/ChatComposer/ChatBindings`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro dei binding UI/runtime collegati al composer

## Changes
- `App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartB_ComposerUI.swift`
- `App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartB_SidebarsAndSwarm.swift`
- `App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartK_ComposerReplyAttachments.swift`
- `App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartH_ComposerMode.swift`
- `App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartH_CodeReviewModes.swift`
- `Config/validation/rust-cutover-swift-allowlist.txt`
  - aggiunta la classificazione `Services/ChatComposer/**`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ProviderFactoryCodeReviewTests -only-testing:SoloCodeAppTests/ChatPanelBuildBehaviorTests -only-testing:SoloCodeAppTests/ChatBackgroundExecutionStateTests -only-testing:SoloCodeAppTests/ComposerRuntimeTimerTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartB_ComposerUI.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/Composer,App/SoloCodeApp/Sources/Chat/Support/Extensions/ComposerUI/ChatPanelView+PartH_ComposerMode.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ComposerUI/ChatPanelView+PartH_CodeReviewModes.swift,App/SoloCodeApp/Sources/Services/ChatComposer,Config/validation/rust-cutover-swift-allowlist.txt,Solo Code.xcodeproj/project.pbxproj'`
