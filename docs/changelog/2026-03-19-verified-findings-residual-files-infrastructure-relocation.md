# 2026-03-19 - Verified findings residual files infrastructure relocation

## Modifiche
- ricollocati in infrastruttura review-core gli ultimi 3 file ancora conteggiati nel prefisso hard-fail `VerifiedFindingsCore`:
  - `VerifiedFindingsLifecycleCommandService.swift` -> `Infrastructure/ReviewCore/VerifiedFindings/Commands`
  - `VerifiedFindingModels.swift` -> `Infrastructure/ReviewCore/VerifiedFindings/Domain`
  - `VerifiedFindingModels+PatchRun.swift` -> `Infrastructure/ReviewCore/VerifiedFindings/Domain`
- aggiornati i path nel progetto Xcode

## Effetto
- il prefisso `Engine/CoderEngine/Sources/VerifiedFindingsCore` viene drenato completamente dal backlog strict review-scope
- il residuo misurato resta concentrato solo nel motore `Engine/CoderEngine/Sources/CodeReview`

## Verifica prevista
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests -only-testing:CoderEngineTests/VerifiedFindingsServiceTests`
- audit strict review-scope
