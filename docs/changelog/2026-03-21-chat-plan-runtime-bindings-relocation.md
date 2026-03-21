# 2026-03-21 chat plan runtime bindings relocation

## Summary
- spostato il cluster `Plan` runtime/binding fuori da `Chat` in `Services/ChatPlan/Runtime`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro dei binding del plan flow durante il cutover

## Changes
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_Phase3.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartN_ClarificationHeuristics.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartO_PlanPromptBuilders.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PlanContinuation.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PlanArtifactVisibility.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartJ_PlanChoice.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartK_PlanExecution.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartN_PlanPrompts.swift`
- `Config/validation/rust-cutover-swift-allowlist.txt`
  - aggiunta la classificazione `Services/ChatPlan/Runtime/**`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PlanBuildIntegrationFlowTests -only-testing:SoloCodeAppTests/PlanOutputClassifierTests -only-testing:SoloCodeAppTests/PlanQuestionPhaseDecisionTests -only-testing:SoloCodeAppTests/PlanFlowPhaseTests -only-testing:SoloCodeAppTests/PlanPanelWorkspacePolicyTests -only-testing:SoloCodeAppTests/PlanShortcutAndCommandTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Support/Extensions/Plan,App/SoloCodeApp/Sources/Chat/Support/Extensions/Core/ChatPanelView+PlanArtifactVisibility.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartJ_PlanChoice.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartK_PlanExecution.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartN_PlanPrompts.swift,App/SoloCodeApp/Sources/Services/ChatPlan/Runtime,Config/validation/rust-cutover-swift-allowlist.txt,Solo Code.xcodeproj/project.pbxproj'`
