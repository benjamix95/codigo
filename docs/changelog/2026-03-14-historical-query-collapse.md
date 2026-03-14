# 2026-03-14 — Historical query collapse

## Modifiche
- rimosso [HistoricalFindingsQueryService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/HistoricalFindingsQueryService.swift)
- consolidati DTO e helper storici in [VerifiedFindingsQueryService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsQueryService.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservata la lettura della history workspace-scoped e lo shaping Rust dei record storici

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/historical-query-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/historical-query-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/historical-query-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/historical-query-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/historical-query-source-packages" -only-testing:CoderEngineTests/VerifiedFindingsQueryServiceTests -only-testing:CoderEngineTests/HistoricalFindingsQueryServiceTests`

## Note
- questa tranche riduce il debito Swift non-UI di `VerifiedFindingsCore` senza introdurre nuovi file
