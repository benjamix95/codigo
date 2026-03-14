# 2026-03-14 — review audit impact collapse

## Cosa cambia
- rimosso `CodeReviewAuditService+Impact.swift`
- consolidati in `CodeReviewAuditService+Bug.swift`:
  - `runBugTestImpactAudit(...)`
  - `runBugDependencyDriftAudit(...)`
  - `runBugDiffSemanticsAudit(...)`
- aggiunta regressione su dependency drift in `CodeReviewAuditAdvancedTests`
- rimosso il riferimento del file dal progetto Xcode

## Perché
- i tre tool erano parte dello stesso perimetro bug audit ma restavano isolati in un file Swift legacy separato

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService+Bug.swift,Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService+Impact.swift,Tests/CoderEngineTests/CodeReview/CodeReviewAuditAdvancedTests.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests/testBugTestImpactFlagsPublicSymbolsWithoutTests -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests/testBugDependencyDriftFlagsChangedLockfile -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests/testCorrelateResultsBuildsClusters`
