# 2026-03-14 — Review live mutation fallback hardening

## Obiettivo
- Ripristinare il contratto di mutazione live del panel review quando il runtime Rust non è disponibile, senza aprire un refactor largo.

## Modifiche
- aggiunto fallback Swift in `ReviewSessionRegistry` per `apply_fix`, `dismiss`, `comment` e `configure`
- corretto `CodeReviewPanelStore.dismissFinding(...)` per ingestare subito lo snapshot live aggiornato
- corretto `mutateSnapshotUsingRust(...)` con fallback locale per `dismiss` sulle sessioni non live
- ripristinato `@testable import CoderEngine` in `CodeReviewPanelLiveRunExecutionTests.swift` per chiudere la regressione di build del merge precedente

## Riduzione debito hard-fail richiesta dal gate
- eliminato `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/CodeReviewMultiSwarmProvider+PipelineBridge.swift`, assorbito in `ReviewPipelineRustDriver.swift`
- eliminato `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ActionOutputFormatting.swift`, assorbito in `ReviewPanelCoordinator.swift`
- aggiornato `Solo Code.xcodeproj/project.pbxproj`

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh ...`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
- `./scripts/bootstrap_test_bundles.sh`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelLiveMutationRustTests -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelDismissFallbackUsesRustMutationAndMarksWontFix -only-testing:SoloCodeAppTests/ReviewPipelineNoFilesMessageTests`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests/testSortedWorkerTaskIDsForDisplay_usesNaturalOrdering -only-testing:CoderEngineTests/ReviewSessionRegistryTests`

## Esito
- dismiss live/fallback del panel review ripristinato
- fallback `configure` del registry ripristinato
- build `SoloCodeAppTests` nuovamente verde
- tranche gate review verde con riduzione reale del debito nei prefissi toccati
