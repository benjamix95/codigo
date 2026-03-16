# 2026-03-16 - VerifiedFindings Rust services ricollocati in Infrastructure

## Tranche completata
- ricollocati sotto `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/VerifiedFindings/`:
  - `Sync/VerifiedFindingsSessionSyncService.swift`
  - `Sync/VerifiedFindingsSessionSyncService+Artifacts.swift`
  - `Sync/VerifiedFindingsSessionSyncService+Mappings.swift`
  - `Replay/VerifiedFindingsService.swift`
  - `Status/VerifiedFindingsStatusService.swift`
- aggiornato `Solo Code.xcodeproj/project.pbxproj`

## Verifica eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsSessionSyncServiceTests -only-testing:CoderEngineTests/VerifiedFindingsServiceTests -only-testing:CoderEngineTests/VerifiedFindingsStatusServiceTests -only-testing:CoderEngineTests/VerifiedFindingsReplayServiceTests -only-testing:CoderEngineTests/VerifiedFindingsProjectionBuilderTests`
- audit strict review-scope:
  - prima: `37` legacy non-UI
  - dopo: `32` legacy non-UI

## Note
- questa tranche non introduce nuova logica Swift; riallinea solo servizi gia' Rust-backed al layer infrastrutturale corretto
- il debito review residuo resta ora concentrato in:
  - `Engine/CoderEngine/Sources/CodeReview`: `24`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore`: `8`
- `xcodebuildmcp` non e' esposto in questo ambiente; la validazione Apple e' stata eseguita con `xcodebuild` diretto
