# 2026-03-14 — verified findings projection builder collapse

## Cosa cambia
- rimosso `VerifiedFindingsProjectionBuilder.swift`
- spostati in `VerifiedFindingsCanonicalStore.swift`:
  - `VerifiedFindingListItemProjection`
  - `VerifiedFindingsProjectionSnapshot`
- spostati in `VerifiedFindingsStatusService.swift`:
  - `VerifiedFindingsProjectionBuilder`
  - `ReviewCoreProjectionRequest`
  - `ReviewCoreProjectionBridgeResponse`
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file projection era rimasto come frammento Swift legacy senza un boundary separato reale

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCanonicalStore.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsStatusService.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Projection/VerifiedFindingsProjectionBuilder.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsProjectionBuilderTests -only-testing:CoderEngineTests/VerifiedFindingsServiceTests -only-testing:CoderEngineTests/VerifiedFindingsStatusServiceTests`
