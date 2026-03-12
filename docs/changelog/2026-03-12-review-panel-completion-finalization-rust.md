# 2026-03-12 - Review panel completion finalization target selection via Rust

## Modifiche
- aggiunto `Native/RustCore/src/review_finalize.rs` con il reducer `select_patch_finalization_targets`.
- esteso `review_core_reduce_panel_state` con l'operazione `derive_patch_finalization_targets`.
- aggiunto `CodeReviewPanelStore+RustCompletionFinalization.swift` come adapter panel-side.
- `CodeReviewPanelStore+CompletionFinalization.swift` ora delega a Rust la selezione dei finding da passare a `prepareVerifiedPatches`.
- aggiunto test Rust sul reducer di finalizzazione e test Swift su `patchFinalizationTargets(for:)`.
- aggiornato `Solo Code.xcodeproj/project.pbxproj` per includere il nuovo file Swift nel target app.

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests`

## Note
- la suite Rust e' verde.
- il build app-side passa; il run della suite continua a bloccarsi nell'ambiente locale su launch della app di test.

## Esito
- il panel non decide piu' localmente quali finding verificati richiedono auto-prepare a review completata
- la selezione dei target di finalizzazione converge sul core Rust
