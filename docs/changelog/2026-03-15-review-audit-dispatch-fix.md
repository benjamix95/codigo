# 2026-03-15 — Review audit dispatch fix

## Modifiche
- corretto [CodeReviewAuditService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService.swift) per instradare i tool security avanzati ai path Swift locali corretti
- corretto il ramo `unsupported` per i tool ignoti senza bridge disponibile
- eliminato [CodeReviewAuditService+Security.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService+Security.swift)
- spostata in [CodeReviewAuditService+SecurityAdvanced.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService+SecurityAdvanced.swift) la sola logica dependency/supply-chain ancora usata
- aggiunto un test mirato in [CodeReviewAuditAdvancedTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/CodeReviewAuditAdvancedTests.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj)

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh ...`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests`
