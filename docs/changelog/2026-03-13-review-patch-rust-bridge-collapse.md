# 2026-03-13 — Review patch Rust bridge collapse

## Modifiche
- rimosso [ReviewPatchRustBridge.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/ReviewPatchRustBridge.swift)
- spostati i DTO patch runtime in [VerifiedFindingsCanonicalStore.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCanonicalStore.swift)
- spostato il queue context rust in [VerifiedFindingsLifecycleCommandService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsLifecycleCommandService.swift)
- spostati runtime start/result e il fallback `close_finding` in [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift)
- consolidati `upsertingPatch` e `closeFinding` in [VerifiedFindingsService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsService.swift)

## Comportamento
- nessun cambiamento funzionale del patch workflow review
- eliminato un wrapper Swift standalone nel dominio `VerifiedFindingsCore`
- preservato il comportamento del caso `close_finding` coperto da regressione app-side

## Validazione eseguita
- `xcodebuild build -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
- `xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests`

## Note
- questa tranche elimina un bridge engine-side puro verso Rust
- il prossimo target sensato nel dominio review resta uno dei file store panel ancora davvero Swift-owned
