# 2026-03-14 — Session projection bridge collapse

## Modifiche
- rimosso [CodeReviewSessionSnapshot+VerifiedFindingsProjection.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Bridges/CodeReviewSessionSnapshot+VerifiedFindingsProjection.swift)
- consolidati `verifiedFindingsProjection` e `canonicalVerifiedFindingsSnapshot` in [CodeReviewSessionSnapshot+Derived.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewSessionSnapshot+Derived.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservato il forwarding dallo snapshot verso `VerifiedFindingsService`

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/session-projection-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/session-projection-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/session-projection-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/session-projection-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/session-projection-source-packages" -only-testing:CoderEngineTests/VerifiedFindingsServiceTests -only-testing:CoderEngineTests/VerifiedFindingsStatusServiceTests`

## Note
- questa tranche riduce il debito Swift non-UI del dominio review senza introdurre nuovi file
