# 2026-03-19 — Verified findings lifecycle rust queue only

## Modifiche
- [VerifiedFindingsLifecycleCommandService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsLifecycleCommandService.swift) usa ora solo:
  - `review_core_patch_workflow` per il `queue_context`
  - `enqueueCodeReviewCommandRustOnly(...)` per l’enqueue reale
- rimossi i fallback enqueue Swift dal lifecycle service
- aggiunti nuovi errori fail-closed:
  - `rustPatchQueueContextUnavailable`
  - `rustReviewQueueUnavailable`
- aggiornato il mapping errori nel wrapper [CodeReviewHandler+PatchWorkflow.swift](/Users/benjaminstoica/SoloCode/Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/ReviewBootstrap/CodeReviewHandler+PatchWorkflow.swift)
- aggiunte regressioni in [VerifiedFindingsStartCommandServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/VerifiedFindings/VerifiedFindingsStartCommandServiceTests.swift)

## Motivazione
- ridurre il backlog finale in `VerifiedFindingsCore` togliendo un altro fallback Swift da una zona critica di queue/state orchestration

## Verifica
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests -only-testing:CoderEngineTests/VerifiedFindingsLifecycleCommandFailClosedTests`

## Note
- I test nominali Rust-gated vengono `skip` nell’host XCTest quando il dylib Rust non è caricabile; la regressione fail-closed resta eseguita.
