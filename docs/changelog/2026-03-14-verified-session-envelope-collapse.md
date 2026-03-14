# 2026-03-14 — Verified session envelope collapse

## Modifiche
- rimosso [VerifiedFindingsSessionEnvelope.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsSessionEnvelope.swift)
- consolidato `VerifiedFindingsSessionEnvelope` in [VerifiedFindingsService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsService.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservata la risoluzione dell'envelope da service, replay e checkpoint

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/session-envelope-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/session-envelope-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/session-envelope-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/session-envelope-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/session-envelope-source-packages" -only-testing:CoderEngineTests/VerifiedFindingsServiceTests -only-testing:CoderEngineTests/VerifiedFindingsReplayServiceTests`

## Note
- questa tranche riduce il debito Swift non-UI di `VerifiedFindingsCore` senza introdurre nuovi file
