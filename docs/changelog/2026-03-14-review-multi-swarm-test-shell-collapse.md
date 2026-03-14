# 2026-03-14 — review multi-swarm test shell collapse

## Cosa cambia
- rimosso `CodeReviewMultiSwarmProviderTests.swift`
- spostata la dichiarazione `CodeReviewMultiSwarmProviderTests: XCTestCase` in `CodeReviewMultiSwarmProviderTests+Outcomes.swift`
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file base della suite era un residuo minimo che conteneva solo il guscio `XCTestCase`

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Tests/CoderEngineTests/CodeReview/CodeReviewMultiSwarmProviderTests.swift,Tests/CoderEngineTests/CodeReview/CodeReviewMultiSwarmProviderTests+Outcomes.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests`
