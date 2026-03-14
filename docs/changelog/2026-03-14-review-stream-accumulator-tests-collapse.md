# 2026-03-14 — review stream accumulator tests collapse

## Cosa cambia
- rimosso `CodeReviewStreamTextAccumulatorTests.swift`
- spostati in `CodeReviewMultiSwarmProviderTests+Outcomes.swift`:
  - `testStreamAccumulatorConsumeResetsVisibleTextOnReplace`
  - `testStreamAccumulatorConsumeIgnoresNonTextEvents`
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file test dedicato era un residuo minimo della suite provider review

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Tests/CoderEngineTests/CodeReview/CodeReviewMultiSwarmProviderTests+Outcomes.swift,Tests/CoderEngineTests/CodeReview/CodeReviewStreamTextAccumulatorTests.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests`
