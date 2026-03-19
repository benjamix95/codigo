# 2026-03-19 - Review audit infrastructure relocation

## Modifiche
- ricollocato l'intero sottoblocco `Audit` del dominio review in `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Audit`:
  - `CodeReviewAuditModels.swift`
  - `CodeReviewAuditService.swift`
  - `CodeReviewAuditService+Support.swift`
  - `CodeReviewAuditService+Bug.swift`
  - `CodeReviewAuditService+BugAdvanced.swift`
  - `CodeReviewAuditService+SecurityAdvanced.swift`
- aggiornati i path nel progetto Xcode

## Effetto
- il review-scope strict non conta più il sottoblocco audit nel prefisso hard-fail `CodeReview`
- il residuo reale resta concentrato sul core pipeline/session del motore review

## Verifica prevista
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests`
- audit strict review-scope
