# 2026-03-14 — Review stream text accumulator collapse

## Modifiche
- rimosso [CodeReviewStreamTextAccumulator.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/Streaming/CodeReviewStreamTextAccumulator.swift)
- consolidato `CodeReviewStreamTextAccumulator` in [CodeReviewMultiSwarmProvider+Types.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/CodeReviewMultiSwarmProvider+Types.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservata la semantica di `textDelta` e `textReplace`

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/review-stream-accumulator-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-stream-accumulator-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/review-stream-accumulator-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/review-stream-accumulator-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-stream-accumulator-source-packages" -only-testing:CoderEngineTests/CodeReviewStreamTextAccumulatorTests`

## Note
- questa tranche riduce il debito Swift non-UI del dominio review core senza introdurre nuovi file
