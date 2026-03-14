# 2026-03-14 — Verified projection models collapse

## Modifiche
- rimosso [VerifiedFindingsProjectionModels.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Projection/VerifiedFindingsProjectionModels.swift)
- consolidati `VerifiedFindingListItemProjection` e `VerifiedFindingsProjectionSnapshot` in [VerifiedFindingsProjectionBuilder.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Projection/VerifiedFindingsProjectionBuilder.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservata la materializzazione delle code candidate e verified della projection

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/projection-models-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/projection-models-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/projection-models-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/projection-models-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/projection-models-source-packages" -only-testing:CoderEngineTests/VerifiedFindingsProjectionBuilderTests`

## Note
- questa tranche riduce il debito Swift non-UI di `VerifiedFindingsCore` senza introdurre nuovi file
