# 2026-03-14 — review chat message context tests collapse

## Cosa cambia
- rimosso `ReviewPanelChatMessageContextTests.swift`
- spostati i test di context extraction in `ReviewPanelChatStructuredContentTests.swift`
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file test dedicato era un residuo minimo della suite panel chat review

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Tests/SoloCodeAppTests/ReviewPanelChatStructuredContentTests.swift,Tests/SoloCodeAppTests/ReviewPanelChatMessageContextTests.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelChatStructuredContentTests`
