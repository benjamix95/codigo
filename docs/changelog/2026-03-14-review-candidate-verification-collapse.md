# 2026-03-14 — Review candidate verification collapse

## Modifiche
- rimosso [ReviewCandidateVerificationService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Verification/ReviewCandidateVerificationService.swift)
- consolidati service, result type e payload FFI in [ReviewPipelineCoordinator+CandidateVerification.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/ReviewPipelineCoordinator+CandidateVerification.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj)

## Comportamento
- nessun cambiamento funzionale previsto
- la candidate verification resta invariata ma meno frammentata

## Validazione eseguita
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/ReviewPipelineCoordinator+CandidateVerification.swift,Engine/CoderEngine/Sources/CodeReview/Verification/ReviewCandidateVerificationService.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `./scripts/bootstrap_test_bundles.sh`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewCandidateVerificationServiceTests`

## Note
- questa tranche riduce il debito Swift non-UI review senza introdurre nuovi file
