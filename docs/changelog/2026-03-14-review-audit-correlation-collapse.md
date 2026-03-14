# 2026-03-14 — Review audit correlation collapse

## Modifiche
- rimosso [CodeReviewAuditService+Correlation.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService+Correlation.swift)
- consolidati `correlateFindings`, `runProfile` e `correlateResults` in [CodeReviewAuditService+Support.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService+Support.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj)

## Comportamento
- nessun cambiamento funzionale previsto
- gli helper audit correlation/profile restano invariati ma meno frammentati

## Validazione eseguita
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService+Support.swift,Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService+Correlation.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests/testCorrelateResultsBuildsClusters -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests/testRunProfileSecurityDeepIncludesAdvancedSecurityTools -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests/testVerificationHintsContainNoEmptyStrings`

## Note
- la suite completa `CodeReviewAuditAdvancedTests` resta rumorosa su path non toccati; il bug è stato registrato separatamente
