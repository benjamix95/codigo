# 2026-03-14 — Review pipeline coordinator collapse

## Modifiche
- rimosso [ReviewPipelineCoordinator.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/ReviewPipelineCoordinator.swift)
- consolidato `ReviewPipelineCoordinator` in [ReviewPipelineCoordinator+Runtime.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/ReviewPipelineCoordinator+Runtime.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservato l'entrypoint `run(...)` verso `ReviewPipelineRustDriver`

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/pipeline-coordinator-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/pipeline-coordinator-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/pipeline-coordinator-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/pipeline-coordinator-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/pipeline-coordinator-source-packages" -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`

## Note
- questa tranche riduce il debito Swift non-UI del dominio review core senza introdurre nuovi file
