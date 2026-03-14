# 2026-03-14 — MCP shared code review command tests collapse

## Modifiche
- eliminato `Tests/CoderEngineTests/CodeReview/MCPSharedCodeReviewCommandsTests.swift`
- consolidata la classe `MCPSharedCodeReviewCommandsTests` in `Tests/CoderEngineTests/CodeReview/CodeReviewSessionStateTests+TerminalLifecycle.swift`
- aggiornato `Solo Code.xcodeproj/project.pbxproj`

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh ...`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSharedCodeReviewCommandsTests`
