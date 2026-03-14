# 2026-03-14 — Verified replay service collapse

## Modifiche
- rimosso [VerifiedFindingsReplayService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsReplayService.swift)
- consolidati `VerifiedFindingsReplayReport` e le API `replay(...)` in [VerifiedFindingsService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsService.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservato il replay dell'envelope e il fallback Rust quando disponibile

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/replay-service-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/replay-service-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/replay-service-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/replay-service-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/replay-service-source-packages" -only-testing:CoderEngineTests/VerifiedFindingsServiceTests -only-testing:CoderEngineTests/VerifiedFindingsReplayServiceTests`

## Note
- questa tranche riduce il debito Swift non-UI di `VerifiedFindingsCore` senza introdurre nuovi file
