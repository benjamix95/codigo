# 2026-03-14 — review handler resolution collapse

## Cosa cambia
- rimosso `CodeReviewHandler+Resolution.swift`
- spostati in `CodeReviewHandler+Start.swift`:
  - `reviewSessionIdPattern`
  - `validReviewBackends`
  - `validateReviewBackend(_:)`
  - `validateReviewSessionIdFormat(_:)`
- spostati in `CodeReviewRustHandlerSupport.swift`:
  - `resolveReviewConversationId(_:)`
  - `resolveReviewSessionId(...)`
  - `reviewScopedSnapshots(...)`
- spostati in `CodeReviewHandler+PatchWorkflow.swift`:
  - `reviewCommandQueued(...)`
  - `validateReviewSessionAccess(...)`
  - `validateFindingOwnership(...)`
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file resolution era rimasto come frammento Swift legacy senza un boundary separato reale

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+Start.swift,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewRustHandlerSupport.swift,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+PatchWorkflow.swift,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+Resolution.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests+SessionResolution -only-testing:CoderEngineTests/CodeReviewHandlerTests+PatchLifecycle -only-testing:CoderEngineTests/MCPSharedCodeReviewCommandsTests`
