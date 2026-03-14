# 2026-03-14 — review provider outcomes tests collapse

## Cosa cambia
- rimosso `CodeReviewMultiSwarmProviderTests+Outcomes.swift`
- spostati i test outcomes/provider nel file `CodeReviewMultiSwarmProviderTests+Parsing.swift`
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file test dedicato era un residuo minimo della suite provider review

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Tests/CoderEngineTests/CodeReview/CodeReviewMultiSwarmProviderTests+Parsing.swift,Tests/CoderEngineTests/CodeReview/CodeReviewMultiSwarmProviderTests+Outcomes.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests`
