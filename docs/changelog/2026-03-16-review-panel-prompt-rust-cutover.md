# 2026-03-16 - Review panel prompt Rust cutover

## Cosa ho fatto
- aggiunto un prompt builder Rust in `Native/RustCore/src/review_panel_runtime/prompts.rs`
- esposto il nuovo entrypoint FFI `review_core_panel_build_prompt`
- rimosso il file Swift legacy `ReviewPanelCoordinator+Prompts.swift`
- instradato `ReviewPanelCoordinator` sul bridge Rust, con fallback locale compatto solo per il caso test/runtime senza core Rust caricato
- spostato `CodeReviewPanelModels.swift` e `ReviewPanelChatModels.swift` sotto `Views/Shared` per ricollocarli correttamente nel perimetro UI
- aggiornato `project.pbxproj` ai nuovi path e alla rimozione del file prompt legacy

## Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests -only-testing:SoloCodeAppTests/ReviewPanelChatStructuredContentTests`
- audit review strict:
  - prima: `72` legacy non-UI
  - dopo: `69` legacy non-UI

## Note
- questa tranche non chiude ancora il panel `CodeReview`
- il taglio e' pero' reale: un file di business logic esce da Swift e due file presentation-only smettono di inquinare il backlog non-UI
