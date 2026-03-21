# 2026-03-21 chat message tool trace relocation

## Summary
- spostato il cluster `MessageToolTrace` da `Chat/MessageToolTrace` a `Tasking/Views/MessageToolTrace`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro UI del tool trace

## Changes
- `App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView.swift`
- `App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView+Details.swift`
- `App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView+EventMetadata.swift`
- `App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView+FileChanges.swift`
- `App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView+Helpers.swift`
- `App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView+Loaders.swift`
- `App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView+State.swift`
- `App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView+TraceRow.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path del cluster spostato

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/MessageToolTraceMCPCamelCaseTests -only-testing:SoloCodeAppTests/ToolTraceVisibilityTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/MessageToolTrace,App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace,Solo Code.xcodeproj/project.pbxproj'`
