# 2026-03-19 — Review patch snapshot upsert in Rust

## Modifiche
- esteso `review_core_command_mutate_snapshot` con l’azione Rust `upsert_patch`
- il mutator Rust restituisce ora anche `patches` oltre a `findings` ed `events`
- `ReviewCommandRustBridge.swift` espone `upsertPatchSnapshot(...)`
- `VerifiedFindingsPatchExecutionService.swift` non usa più `VerifiedFindingsService.upsertingPatch(...)` nel path di esecuzione patch; l’upsert canonico passa dal mutator Rust
- aggiunti test Rust per `upsert_patch`
- aggiunti test Swift sul bridge `upsertPatchSnapshot`

## Motivazione
- chiudere l’ultimo bordo Swift-owned del patch lifecycle e rendere la tranche 4 Rust-backed anche sul punto in cui lo snapshot di sessione viene aggiornato con l’artifact patch

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests`
