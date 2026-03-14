# 2026-03-14 — Review command payload helper collapse

## Modifiche
- rimosso [SessionConfig+ReviewCommandPayload.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Session/SessionConfig+ReviewCommandPayload.swift)
- consolidato `SessionConfig.reviewCommandPayload` in [ReviewSessionTypes.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Session/ReviewSessionTypes.swift)
- aggiunta regression in [VerifiedFindingsStartCommandServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/VerifiedFindings/VerifiedFindingsStartCommandServiceTests.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservato il payload review command generato da `SessionConfig`

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/review-command-payload-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-command-payload-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/review-command-payload-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/review-command-payload-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-command-payload-source-packages" -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests/testSessionConfigBuildsReviewCommandPayload`

## Note
- questa tranche riduce il debito Swift non-UI del dominio review session senza introdurre nuovi file
