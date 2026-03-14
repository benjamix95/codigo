# 2026-03-14 — Panel live mutation tests collapse

## Modifiche
- eliminato `Tests/SoloCodeAppTests/CodeReviewPanelLiveMutationRustTests.swift`
- consolidata la classe `CodeReviewPanelLiveMutationRustTests` in `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`
- aggiornato `Solo Code.xcodeproj/project.pbxproj`

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh ...`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelLiveMutationRustTests`
