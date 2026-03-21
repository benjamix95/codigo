# 2026-03-21 chat composer relocation

## Summary
- spostato il cluster `Composer` da `Chat/Composer` e `Chat/ComposerTextView.swift` a `ChatView/Composer`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro UI del composer

## Changes
- `App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView.swift`
- `App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView+Attachments.swift`
- `App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView+Commands.swift`
- `App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView+ComposerBox.swift`
- `App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView+Controls.swift`
- `App/SoloCodeApp/Sources/ChatView/Composer/ComposerTextView.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path del cluster spostato

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ComposerTextViewFocusTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Composer,App/SoloCodeApp/Sources/Chat/ComposerTextView.swift,App/SoloCodeApp/Sources/ChatView/Composer,Solo Code.xcodeproj/project.pbxproj'`
