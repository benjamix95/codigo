# 2026-03-14 — Session state snapshot bridge collapse

## Modifiche
- rimosso [CodeReviewSessionState+RustSnapshot.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/Rust/CodeReviewSessionState+RustSnapshot.swift)
- consolidato `replaceCanonicalSnapshot(_:)` in [CodeReviewSessionState.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewSessionState.swift)
- aggiunta regression in [CodeReviewSessionStateTests+TerminalLifecycle.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/CodeReviewSessionStateTests+TerminalLifecycle.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservata la sostituzione canonica dello snapshot quando il `sessionId` coincide

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/session-state-snapshot-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/session-state-snapshot-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/session-state-snapshot-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/session-state-snapshot-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/session-state-snapshot-source-packages" -only-testing:CoderEngineTests/CodeReviewSessionStateTests/testReplaceCanonicalSnapshotReplacesStateForMatchingSession`

## Note
- questa tranche riduce il debito Swift non-UI del dominio review core senza introdurre nuovi file
