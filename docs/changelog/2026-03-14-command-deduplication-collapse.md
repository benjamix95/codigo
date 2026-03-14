# 2026-03-14 — Command deduplication collapse

## Modifiche
- rimosso [CommandDeduplicationService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/CommandDeduplicationService.swift)
- consolidati `VerifiedCommandDeduplicationRecord` e `CommandDeduplicationService` in [VerifiedFindingsCommandCoordinator.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCommandCoordinator.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservata la deduplica per `commandId` e `requestFingerprint`

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/command-dedup-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/command-dedup-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/command-dedup-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/command-dedup-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/command-dedup-source-packages" -only-testing:CoderEngineTests/CommandDeduplicationServiceTests`

## Note
- questa tranche riduce il debito Swift non-UI di `VerifiedFindingsCore` senza introdurre nuovi file
