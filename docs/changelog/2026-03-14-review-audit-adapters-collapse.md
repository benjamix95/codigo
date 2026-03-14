# 2026-03-14 — review audit adapters collapse

## Cosa cambia
- rimosso `CodeReviewAuditService+Adapters.swift` dal perimetro audit review
- consolidati in `CodeReviewAuditService.swift`:
  - `commandExists(_:)`
  - `runOptionalAdapter(...)`
  - `parseAdapterHint(...)`
- aggiornata la suite `CodeReviewAuditAdvancedTests` con regressioni sui contratti adapter
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file adapter era rimasto come frammento Swift non-UI isolato, senza un boundary separato reale
- il consolidamento riduce il debito legacy del dominio review mantenendo invariato il comportamento osservabile

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService.swift,Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService+Adapters.swift,Tests/CoderEngineTests/CodeReview/CodeReviewAuditAdvancedTests.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests/testRunOptionalAdapterReturnsUnavailableWhenCommandMissing -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests/testParseAdapterHintBuildsSecurityFindingWhenMatcherPresent -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests/testCorrelateResultsBuildsClusters -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests/testRunToolDurationMsIsPositive`
