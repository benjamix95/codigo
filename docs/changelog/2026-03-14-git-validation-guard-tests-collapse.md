# 2026-03-14 — Git validation guard tests collapse

## Modifiche
- eliminato `Tests/SoloCodeAppTests/GitServiceValidationGuardTests.swift`
- consolidata la classe `GitServiceValidationGuardTests` in `Tests/SoloCodeAppTests/CheckpointGitStoreTests.swift`
- aggiornato `Solo Code.xcodeproj/project.pbxproj`

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh ...`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/GitServiceValidationGuardTests -only-testing:SoloCodeAppTests/CheckpointGitStoreTests`
