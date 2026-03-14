# 2026-03-14 — Verified checkpoint collapse

## Modifiche
- rimosso [VerifiedFindingsCheckpointService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCheckpointService.swift)
- spostati `VerifiedFindingsEnvelopeSource` e `VerifiedFindingsRecoveredEnvelope` in [VerifiedFindingsService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsService.swift)
- spostato `VerifiedFindingsCheckpointService` in [VerifiedFindingsStatusService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsStatusService.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj)

## Comportamento
- nessun cambiamento funzionale previsto
- il recovery verified findings resta invariato ma meno frammentato

## Validazione eseguita
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsService.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsStatusService.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCheckpointService.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `./scripts/bootstrap_test_bundles.sh`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsReplayServiceTests`

## Note
- questa tranche riduce il debito Swift non-UI di `VerifiedFindingsCore` senza introdurre nuovi file
