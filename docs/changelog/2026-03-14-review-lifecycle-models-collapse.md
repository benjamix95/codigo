# 2026-03-14 — review lifecycle models collapse

## Cosa cambia
- rimosso `ReviewLifecycleModels.swift`
- spostati in `CodeReviewFinding+Factories.swift`:
  - `ReviewCandidateStatus`
  - `ReviewSignalType`
  - `ReviewCandidate`
- spostati in `CodeReviewSessionState+CandidatesAndPatches.swift`:
  - `ReviewPatchStatus`
  - `ReviewPatchVerifyStatus`
  - `ReviewPatchPRStatus`
  - `ReviewPatchMergeStatus`
  - `ReviewPatchArtifact`
- spostato in `CodeReviewSessionSnapshot+Derived.swift`:
  - `ReviewSessionOutcome`
- aggiunta regressione su `buildOutcomeSummary()` in `ReviewSessionRegistryTests`
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file lifecycle era rimasto come frammento Swift legacy senza un boundary separato reale

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewFinding+Factories.swift,Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewSessionState+CandidatesAndPatches.swift,Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewSessionSnapshot+Derived.swift,Engine/CoderEngine/Sources/CodeReview/Session/ReviewLifecycleModels.swift,Tests/CoderEngineTests/CodeReview/ReviewSessionRegistryTests.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewFindingTests -only-testing:CoderEngineTests/ReviewSessionRegistryTests/testBuildOutcomeSummaryCountsPatchStatesAndManualActions`

## Rischi residui
- la suite completa `ReviewSessionRegistryTests` resta rossa su path di mutazione Rust live non toccati da questa tranche; il bug è registrato separatamente in `docs/bugs/P2-2026-03-14-review-session-registry-suite-remains-red-on-unrelated-rust-mutation-paths.md`
