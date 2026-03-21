# 2026-03-21 chat message row relocation

## Summary
- spostato il cluster `MessageRow` da `Chat/MessageRow` a `ChatView/MessageRow`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro UI delle row messaggi

## Changes
- `App/SoloCodeApp/Sources/ChatView/MessageRow/MessageRow.swift`
- `App/SoloCodeApp/Sources/ChatView/MessageRow/MessageRow+Content.swift`
- `App/SoloCodeApp/Sources/ChatView/MessageRow/MessageRow+ImageCache.swift`
- `App/SoloCodeApp/Sources/ChatView/MessageRow/MessageRow+Indicators.swift`
- `App/SoloCodeApp/Sources/ChatView/MessageRow/MessageRow+Thinking.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path del cluster spostato

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/MessageRowCopyEligibilityTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/MessageRow,App/SoloCodeApp/Sources/ChatView/MessageRow,Solo Code.xcodeproj/project.pbxproj'`
