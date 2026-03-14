# 2026-03-14 — review file lock coordinator collapse

## Cosa cambia
- rimosso `FileLockCoordinator.swift`
- spostato `FileLockCoordinator` in `CodeReviewSessionState.swift`
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file locking era rimasto come residuo Swift legacy anche se il tipo appartiene al runtime review/session

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewSessionState.swift,Engine/CoderEngine/Sources/CodeReview/Locking/FileLockCoordinator.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/FileLockCoordinatorTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
