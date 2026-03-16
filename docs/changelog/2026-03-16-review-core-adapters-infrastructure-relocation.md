# 2026-03-16 - Review core adapters ricollocati in Infrastructure

## Tranche completata
- ricollocati sotto `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/`:
  - `Identity/FindingIdentityService.swift`
  - `Pipeline/ReviewPipelineCoordinator+CandidateVerification.swift`
  - `Pipeline/ReviewPipelineRustDriver.swift`
  - `Pipeline/ReviewPipelineRustModels.swift`
  - `Pipeline/ReviewRuntimeAdapter.swift`
- aggiornato `Solo Code.xcodeproj/project.pbxproj`

## Verifica eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/FindingIdentityServiceTests -only-testing:CoderEngineTests/ReviewCandidateVerificationServiceTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- audit strict review-scope:
  - prima: `42` legacy non-UI
  - dopo: `37` legacy non-UI

## Note
- questa tranche non introduce nuova logica Swift: sposta solo adapter/DTO/orchestrator host gia' legati al review core Rust
- il debito review residuo resta confinato a:
  - `Engine/CoderEngine/Sources/CodeReview`: `24`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore`: `13`
- `xcodebuildmcp` non e' esposto in questo ambiente; la validazione Apple e' stata eseguita con `xcodebuild` diretto
