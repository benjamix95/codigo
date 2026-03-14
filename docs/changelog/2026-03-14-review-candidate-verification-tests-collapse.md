# 2026-03-14 — review candidate verification tests collapse

## Cosa cambia
- rimosso `ReviewCandidateVerificationServiceTests.swift`
- spostati i test candidate verification in `ReviewDiffSummaryServiceTests.swift`
- mantenuta una classe `ReviewCandidateVerificationServiceTests` separata nel file di destinazione
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file test dedicato era un residuo minimo della suite engine-side review services

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Tests/CoderEngineTests/CodeReview/ReviewDiffSummaryServiceTests.swift,Tests/CoderEngineTests/CodeReview/ReviewCandidateVerificationServiceTests.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewCandidateVerificationServiceTests`
