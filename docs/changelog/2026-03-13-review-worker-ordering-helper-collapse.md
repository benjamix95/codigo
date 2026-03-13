# 2026-03-13 — Review worker ordering helper collapse

## Modifiche
- rimosso [CodeReviewMultiSwarmProvider+WorkerOrdering.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/CodeReviewMultiSwarmProvider+WorkerOrdering.swift)
- consolidati gli helper statici di worker ordering in [CodeReviewMultiSwarmProvider+Types.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/CodeReviewMultiSwarmProvider+Types.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservato l'ordinamento naturale dei worker `review-1`, `review-2`, `review-10`

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/review-worker-ordering-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-worker-ordering-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/review-worker-ordering-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/review-worker-ordering-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-worker-ordering-source-packages" -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests/testSortedWorkerTaskIDsForDisplay_usesNaturalOrdering -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests/testSortedReviewWorkerPlanActivitiesForDisplay_usesNaturalWorkerOrdering`

## Note
- questa tranche riduce il debito Swift non-UI del dominio review engine senza introdurre nuovi file
