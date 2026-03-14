# 2026-03-14 — Multi-swarm config collapse

## Modifiche
- rimosso [MultiSwarmReviewConfig.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/MultiSwarmReviewConfig.swift)
- consolidati `ReviewEnabledPhase` e `MultiSwarmReviewConfig` in [CodeReviewMultiSwarmProvider.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/CodeReviewMultiSwarmProvider.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservata la configurazione di worker, phases, rounds e backend del provider review

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/multi-swarm-config-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/multi-swarm-config-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/multi-swarm-config-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/multi-swarm-config-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/multi-swarm-config-source-packages" -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`

## Note
- questa tranche riduce il debito Swift non-UI del dominio review core senza introdurre nuovi file
