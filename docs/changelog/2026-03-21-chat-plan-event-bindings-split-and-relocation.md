# 2026-03-21 chat plan event bindings split and relocation

## Summary
- spostato `ChatPanelView+PartF_PlanEvents.swift` fuori da `Chat` in `Services/ChatTaskTrace/Bindings`
- spezzato il file in due unita' sotto soglia, estraendo gli helper privati in `ChatPanelView+PartF_PlanEventHelpers.swift`
- nessuna modifica di logica di produzione; solo split ordinato e riallineamento del perimetro

## Changes
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEvents.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEventHelpers.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornato il path del file spostato
  - aggiunto il nuovo file helper al target app

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PlanShortcutAndCommandTests -only-testing:SoloCodeAppTests/PlanPanelWorkspacePolicyTests -only-testing:SoloCodeAppTests/TodoStoreTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_PlanEvents.swift,App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEvents.swift,App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEventHelpers.swift,Solo Code.xcodeproj/project.pbxproj'`
