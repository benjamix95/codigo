# 2026-03-21 chat task status relocation

## Summary
- spostato il cluster `TaskStatus` da `Chat/TaskStatus` a `Tasking/Views/TaskStatus`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro delle viste/task panel UI

## Changes
- `App/SoloCodeApp/Sources/Tasking/Views/TaskStatus/ChangedFilesSummaryCard.swift`
- `App/SoloCodeApp/Sources/Tasking/Views/TaskStatus/TaskActivityPanel.swift`
- `App/SoloCodeApp/Sources/Tasking/Views/TaskStatus/TaskActivityPanel+Helpers.swift`
- `App/SoloCodeApp/Sources/Tasking/Views/TaskStatus/TaskActivityPanel+Scope.swift`
- `App/SoloCodeApp/Sources/Tasking/Views/TaskStatus/TaskActivityPanel+Standard.swift`
- `App/SoloCodeApp/Sources/Tasking/Views/TaskStatus/TaskControlBar.swift`
- `App/SoloCodeApp/Sources/Tasking/Views/TaskStatus/TaskControlBar+Helpers.swift`
- `App/SoloCodeApp/Sources/Tasking/Views/TaskStatus/TaskStatusModifiers.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path del cluster spostato

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/TaskActivityPanelScopingTests -only-testing:SoloCodeAppTests/TaskActivityPanelInstantGrepSnapshotTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/TaskStatus,App/SoloCodeApp/Sources/Tasking/Views/TaskStatus,Solo Code.xcodeproj/project.pbxproj'`
