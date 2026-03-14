# 2026-03-14 — BugHunter workflow tests collapse

## Modifiche
- eliminato `Tests/CoderEngineTests/CodeReview/BugHunterWorkflowServiceTests.swift`
- consolidata la classe `BugHunterWorkflowServiceTests` in `Tests/CoderEngineTests/CodeReview/CodeReviewMultiSwarmProviderTests+TaskExtraction.swift`
- aggiornato `Solo Code.xcodeproj/project.pbxproj`

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh ...`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/BugHunterWorkflowServiceTests`
