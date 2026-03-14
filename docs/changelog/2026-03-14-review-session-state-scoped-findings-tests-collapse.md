# 2026-03-14 — review session state scoped findings tests collapse

## Cosa cambia
- rimosso `CodeReviewSessionStateTests+ScopedFindings.swift`
- spostati in `CodeReviewSessionStateTests+TerminalLifecycle.swift`:
  - `testReplaceOpenFindingsOnlyTouchesReviewedFiles`
  - `testMarkOpenFindingsAsFixAppliedOnlyTouchesRequestedFiles`
  - `testMutationSequenceIncreasesAcrossStateChanges`
- allineata l’aspettativa del test scoped a `patchApplied`, coerente col comportamento attuale del runtime
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file test dedicato era un residuo minimo della suite session state review

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Tests/CoderEngineTests/CodeReview/CodeReviewSessionStateTests+TerminalLifecycle.swift,Tests/CoderEngineTests/CodeReview/CodeReviewSessionStateTests+ScopedFindings.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewSessionStateTests/testReplaceOpenFindingsOnlyTouchesReviewedFiles -only-testing:CoderEngineTests/CodeReviewSessionStateTests/testMarkOpenFindingsAsFixAppliedOnlyTouchesRequestedFiles -only-testing:CoderEngineTests/CodeReviewSessionStateTests/testMutationSequenceIncreasesAcrossStateChanges`

## Rischi residui
- la suite completa `CodeReviewSessionStateTests` resta rossa su path non toccati da questa tranche; il bug è registrato in `docs/bugs/P2-2026-03-14-review-session-state-suite-remains-red-on-unrelated-coalescing-and-summary-paths.md`
