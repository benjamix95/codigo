# 2026-03-14 — review handler findings output tests collapse

## Cosa cambia
- rimosso `CodeReviewHandlerTests+FindingsOutput.swift`
- spostati in `CodeReviewHandlerTests+Validation.swift`:
  - `testReviewFindingsOmitsSensitiveDetailsFromOutput`
  - `testReviewFindingsDoesNotFallBackToCompletedSessionWhenNoActiveSessionExists`
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file test dedicato era un residuo minimo della suite handler review

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Tests/CoderEngineTests/CodeReview/CodeReviewHandlerTests+Validation.swift,Tests/CoderEngineTests/CodeReview/CodeReviewHandlerTests+FindingsOutput.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests`
