# 2026-03-14 — Review runtime resources collapse

## Modifiche
- rimosso [CodeReviewRuntimeResources.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/CodeReviewRuntimeResources.swift)
- consolidati `ReviewPatchPreparationRuntime`, `CodeReviewRuntimeResources` e `CodeReviewRuntimeResolver` in [ReviewPipelineCoordinator+Runtime.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/ReviewPipelineCoordinator+Runtime.swift)
- aggiunta regression in [ReviewPipelineCoordinatorTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/ReviewPipelineCoordinatorTests.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservata la selezione dei runtime resources statici o risolti via `runtimeResolver`

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/runtime-resources-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/runtime-resources-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/runtime-resources-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/runtime-resources-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/runtime-resources-source-packages" -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`

## Note
- questa tranche riduce il debito Swift non-UI del dominio review core senza introdurre nuovi file
