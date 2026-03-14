# 2026-03-14 — Review provider types collapse

## Modifiche
- rimosso [CodeReviewMultiSwarmProvider+Types.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/CodeReviewMultiSwarmProvider+Types.swift)
- consolidati tipi e helper del provider review in [CodeReviewMultiSwarmProvider.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/CodeReviewMultiSwarmProvider.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservati accumulator, stati di review e ordinamento naturale dei worker

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/provider-types-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/provider-types-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/provider-types-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/provider-types-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/provider-types-source-packages" -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests -only-testing:CoderEngineTests/CodeReviewStreamTextAccumulatorTests`

## Note
- questa tranche riduce il debito Swift non-UI del dominio review core senza introdurre nuovi file
