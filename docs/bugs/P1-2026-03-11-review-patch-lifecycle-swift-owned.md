# P1 — Lifecycle command validation e patch action planning erano ancora decisi da Swift

## Bug Fix Record
- Categoria: A
- Bug: validazione ownership/session/patch readiness e il sequencing delle azioni patch (`prepare/verify/apply/...`) vivevano ancora nei servizi Swift `VerifiedFindingsLifecycleCommandService` e `VerifiedFindingsPatchExecutionService`.
- Sintomo: il core review Rust governava pipeline e MCP, ma patch lifecycle e preconditions restavano in un secondo motore Swift.
- Impatto: rischio di drift semantico tra queue MCP Rust-backed e workflow patch effettivo, con regressioni possibili su `apply_patch`, `apply_fix`, `rollback`, `merge_pr` e ownership checks.
- Gravita': alta, perché tocca patch execution e command validation.
- Steps to reproduce:
  1. Eseguire un comando lifecycle review/security/bughunter su un finding.
  2. Seguire il flusso `VerifiedFindingsLifecycleCommandService -> MCPSharedState.enqueueCodeReviewCommand`.
  3. Osservare che validazione e sequencing patch erano ancora in Swift.
- Risultato attuale: il core Rust deve validare il lifecycle context e pianificare gli step patch; Swift deve solo eseguire side effects concreti.
- Risultato atteso: nessuna precondition patch/finding/session resta nei servizi Swift.
- Causa probabile: tranche precedenti concentrate su pipeline review e MCP shared-state, senza il passaggio finale del patch lifecycle.
- Scope consentito:
  - `Native/RustCore/src/review_patch/*`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/*`
  - `App/SoloCodeApp/Sources/CodeReview/Services/*`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - UI SwiftUI
  - esecuzione concreta Git/Process/PR lato OS
  - provider factory
- Moduli confinanti da verificare:
  - `BugHunterWorkflowServiceTests`
  - `VerifiedFindingsStartCommandServiceTests`
  - `ReviewPatchWorkflowServiceTests`
  - `SoloCodeAppCodeReviewCommandLoopTests`
- Test da aggiungere o aggiornare:
  - unit test Rust su queue context e execution plan
  - regressioni Swift su queueLifecycle/apply_patch context
  - smoke app-side sul command loop review
- Strategia di fix minimo:
  - introdurre `review_patch` nel core Rust
  - aggiungere `ReviewPatchRustBridge`
  - far usare a `VerifiedFindingsLifecycleCommandService` e `VerifiedFindingsPatchExecutionService` il planner/validator Rust
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test ... -only-testing:CoderEngineTests/BugHunterWorkflowServiceTests -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests`
  - `xcodebuild test ... -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests`
- Commit previsto: `perf(review): move patch lifecycle planning into rust core`
