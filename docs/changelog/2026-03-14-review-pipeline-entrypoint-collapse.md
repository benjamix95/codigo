# 2026-03-14 — Review pipeline entrypoint collapse

## Modifiche
- rimosso [CodeReviewMultiSwarmProvider+Pipeline.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/CodeReviewMultiSwarmProvider+Pipeline.swift)
- consolidato `runReviewPipeline(...)` in [CodeReviewMultiSwarmProvider+PipelineBridge.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/CodeReviewMultiSwarmProvider+PipelineBridge.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservato l'inoltro del provider verso `ReviewPipelineCoordinator.shared.run(...)`

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/pipeline-bridge-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/pipeline-bridge-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/pipeline-bridge-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/pipeline-bridge-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/pipeline-bridge-source-packages" -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`

## Note
- questa tranche riduce il debito Swift non-UI del dominio review core senza introdurre nuovi file
