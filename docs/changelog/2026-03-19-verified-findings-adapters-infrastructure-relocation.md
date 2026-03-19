# 2026-03-19 - VerifiedFindings adapter command/query/security in Infrastructure

## Tranche completata
- ricollocati sotto `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/VerifiedFindings/`:
  - `Canonical/VerifiedFindingsCanonicalStore.swift`
  - `Commands/VerifiedFindingsStartCommandService.swift`
  - `Query/VerifiedFindingsQueryService.swift`
  - `Security/SecurityWorkflowService.swift`
  - `BugHunter/BugHunterAutofixSelectionService.swift`
- aggiornato `Solo Code.xcodeproj/project.pbxproj`

## Verifica eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests -only-testing:CoderEngineTests/VerifiedFindingsCommandCoordinatorTests -only-testing:CoderEngineTests/VerifiedFindingsSecurityGateServiceTests -only-testing:CoderEngineTests/VerifiedFindingsQueryServiceTests -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests+TaskExtraction -only-testing:CoderEngineTests/BugHunterAutofixFilterTests`
- audit strict review-scope:
  - prima: `32` legacy non-UI
  - dopo: `27` legacy non-UI

## Note
- `xcodebuild` ha richiesto escalation fuori sandbox per accedere ai servizi/macOS logs necessari ai test
- questa tranche lascia volontariamente fuori `VerifiedFindingsLifecycleCommandService.swift` perche' e' a `301` righe e richiede split dedicato
- residuo review corrente:
  - `Engine/CoderEngine/Sources/CodeReview`: `24`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore`: `3`
