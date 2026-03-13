# 2026-03-13 — Review Git context Rust cutover

## Modifiche
- introdotto il modulo Rust [review_git_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_git_context.rs)
- aggiunto l'entrypoint FFI [review_panel_git.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_panel_git.rs)
- assorbito `CodeReviewPanelStore+GitContext.swift` in:
  - [CodeReviewPanelStore+ProviderSelection.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ProviderSelection.swift)
  - [CodeReviewPanelStore+Settings.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Settings.swift)
  - [CodeReviewPanelStore+TargetedFix.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+TargetedFix.swift)
- rimosso il file dal filesystem e dal `.pbxproj`

## Comportamento
- il panel review carica branch/commit tramite boundary Rust dedicato
- Swift resta limitato a stato UI-adjacent e selezione locale
- conteggio panel review aggiornato: `26 -> 25`

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml review_git_context -- --nocapture`
- `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ProviderSelection.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Settings.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+TargetedFix.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+GitContext.swift,Native/RustCore/src/lib.rs,Native/RustCore/src/ffi/mod.rs,Native/RustCore/src/review_git_context.rs,Native/RustCore/src/ffi/review_panel_git.rs,"Solo Code.xcodeproj/project.pbxproj",scripts/validate_rust_cutover_boundary.sh`

## Note
- questa tranche sposta davvero logica di caricamento non-UI dal panel review verso Rust
- il prossimo target sensato è `PatchWorkflow` oppure `ProviderSelection` residuo se vogliamo continuare a svuotare il panel store Swift
