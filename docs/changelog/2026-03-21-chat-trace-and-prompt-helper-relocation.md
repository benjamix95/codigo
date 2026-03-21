# 2026-03-21 chat trace and prompt helper relocation

## Summary
- spostato `ChatPanelView+PartG_TraceDebug.swift` in `Services/ChatTaskTrace/Bindings`
- spostato `ChatPanelView+PartL_PromptOptimization.swift` in `Services/ChatComposer/ChatBindings`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro dei binding helper

## Changes
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartG_TraceDebug.swift`
- `App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartL_PromptOptimization.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ToolTraceVisibilityTests -only-testing:SoloCodeAppTests/ProviderFactoryCodeReviewTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartG_TraceDebug.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartL_PromptOptimization.swift,App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartG_TraceDebug.swift,App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartL_PromptOptimization.swift,Solo Code.xcodeproj/project.pbxproj'`
