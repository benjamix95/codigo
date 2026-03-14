# 2026-03-14 — review handler session resolution tests collapse

## Cosa cambia
- rimosso `CodeReviewHandlerTests+SessionResolution.swift`
- spostati in `CodeReviewHandlerTests+Helpers.swift`:
  - `testReviewStatusFallsBackToConversationScopedSessionWhenConversationIdIsOmitted`
  - `testReviewFindingsFallsBackToConversationScopedSessionWhenConversationIdIsOmitted`
  - `testReviewDiffSummaryFallsBackToConversationScopedSessionWhenConversationIdIsOmitted`
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file test dedicato era un residuo minimo della suite handler review

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Tests/CoderEngineTests/CodeReview/CodeReviewHandlerTests+Helpers.swift,Tests/CoderEngineTests/CodeReview/CodeReviewHandlerTests+SessionResolution.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests`
