# 2026-03-21 chat plan flow support relocation

## Summary
- spostati `ChatPanelSupport+PlanFlow.swift`, `ChatPanelSupport+PlanFlowHelpers.swift` e `ChatPanelSupport+PlanQuestionnaire.swift` da `Chat/Support` a `Services/ChatPlan`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro degli helper plan-flow

## Changes
- `App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanFlow.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanFlowHelpers.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanQuestionnaire.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PlanShortcutAndCommandTests -only-testing:SoloCodeAppTests/PlanFlowPhaseTests -only-testing:SoloCodeAppTests/ChatPanelBuildBehaviorTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Support/ChatPanelSupport+PlanFlow.swift,App/SoloCodeApp/Sources/Chat/Support/ChatPanelSupport+PlanFlowHelpers.swift,App/SoloCodeApp/Sources/Chat/Support/ChatPanelSupport+PlanQuestionnaire.swift,App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanFlow.swift,App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanFlowHelpers.swift,App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanQuestionnaire.swift,Solo Code.xcodeproj/project.pbxproj'`
