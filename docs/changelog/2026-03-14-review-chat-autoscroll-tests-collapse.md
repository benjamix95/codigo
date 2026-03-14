# 2026-03-14 — review chat autoscroll tests collapse

## Cosa cambia
- rimosso `ReviewPanelChatAutoscrollTests.swift`
- spostati i test autoscroll in `ReviewPanelChatStructuredContentTests.swift`
- mantenuta una classe `ReviewPanelChatAutoscrollTests` separata nel file di destinazione per preservare la discoverability del runner
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file test dedicato era un residuo minimo della suite panel chat review

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Tests/SoloCodeAppTests/ReviewPanelChatStructuredContentTests.swift,Tests/SoloCodeAppTests/ReviewPanelChatAutoscrollTests.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelChatAutoscrollTests`
