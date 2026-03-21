# 2026-03-21 chat task trace bindings relocation

## Summary
- spostato il cluster `TaskTrace` fuori da `Chat` in `Services/ChatTaskTrace/Bindings`
- lasciato fuori `ChatPanelView+PartF_PlanEvents.swift`, che verra' trattato a parte con split dedicato per restare sotto il limite file
- nessuna modifica di logica di produzione; solo riallineamento del perimetro dei binding task trace

## Changes
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_AutoTodoRuntime.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_CodeReviewActions.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_CodeReviewMutations.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_DebugTodoEvents+Helpers.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_DebugTodoEvents.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_DebugTodoLifecycle.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_TodoEvents.swift`
- `Config/validation/rust-cutover-swift-allowlist.txt`
  - aggiunta la classificazione `Services/ChatTaskTrace/**`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatAutoTodoBoundaryTests -only-testing:SoloCodeAppTests/ChatPanelTodoFinalizationTests -only-testing:SoloCodeAppTests/ChatPanelAutoTodoTracePayloadTests -only-testing:SoloCodeAppTests/TodoStoreTests -only-testing:SoloCodeAppTests/ToolTraceVisibilityTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_AutoTodoRuntime.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_CodeReviewActions.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_CodeReviewMutations.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_DebugTodoEvents+Helpers.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_DebugTodoEvents.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_DebugTodoLifecycle.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_TodoEvents.swift,App/SoloCodeApp/Sources/Services/ChatTaskTrace,Config/validation/rust-cutover-swift-allowlist.txt,Solo Code.xcodeproj/project.pbxproj'`
