# 2026-03-14 — verified finding enums collapse

## Cosa cambia
- rimosso `VerifiedFindingEnums.swift`
- spostati in `VerifiedFindingModels.swift` gli enum del contratto finding/evidence/verification
- spostati in `VerifiedFindingModels+PatchRun.swift` gli enum patch/run
- aggiunta regressione codable in `VerifiedFindingsServiceTests`
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file enum separato era rimasto come residuo Swift legacy senza un boundary tecnico reale

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/VerifiedFindingsCore/Domain/VerifiedFindingModels.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Domain/VerifiedFindingModels+PatchRun.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Domain/VerifiedFindingEnums.swift,Tests/CoderEngineTests/VerifiedFindings/VerifiedFindingsServiceTests.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsServiceTests -only-testing:CoderEngineTests/VerifiedFindingsStatusServiceTests`
