# 2026-03-11 — Review patch close + deferred finalization Rust tranche

## Scope
- chiusura `close_finding` nel core Rust review patch
- finalizzazione dei comandi review deferred nel core Rust review command

## Modifiche
- esteso `Native/RustCore/src/review_patch/` per validare e pianificare `close_finding`
- ampliato il payload `ReviewPatchRustBridge` con stato finding e patch
- aggiornato `VerifiedFindingsPatchExecutionService` per eseguire lo step `close_finding`
- allineato `VerifiedFindingsLifecycleCommandService` al contratto di chiudibilità anche nel fallback Swift
- aggiunto `Native/RustCore/src/review_command/finalize.rs`
- esposto `review_core_command_finalize_deferred` via FFI
- aggiornato `CodigoApp+CodeReviewDeferredCommands.swift` per delegare a Rust la decisione finale `completed/failed`
- aggiunte regressioni app-side su close path e deferred failure path
- aggiunti test engine per la queue `close_finding`

## Validazione
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests -only-testing:CoderEngineTests/BugHunterWorkflowServiceTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`

## Note
La UI resta invariata in Swift. Restano fuori da questa tranche gli artefatti `Native/RustCore/target/` e ogni modifica locale non verificata.
