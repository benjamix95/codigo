# 2026-03-14 — review session event collapse

## Cosa cambia
- rimosso `CodeReviewSessionEvent.swift`
- spostati in `CodeReviewFinding+Factories.swift`:
  - `CodeReviewSessionEvent`
  - `toPayload()`
- spostati in `CodeReviewSessionState+Lifecycle.swift`:
  - `CodeReviewSessionEvent.EventType`
  - factory evento review (`sessionStarted`, `findingAdded`, `roundStarted`, ecc.)
- aggiunta regressione sul payload evento in `CodeReviewFindingTests`
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file evento era rimasto come frammento Swift legacy senza un boundary separato reale

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewFinding+Factories.swift,Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewSessionState+Lifecycle.swift,Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewSessionEvent.swift,Tests/CoderEngineTests/CodeReview/CodeReviewFindingTests.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewFindingTests -only-testing:CoderEngineTests/MCPSharedCodeReviewSnapshotStoreTests`
