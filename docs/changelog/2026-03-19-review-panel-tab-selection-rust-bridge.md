# 2026-03-19 - Review panel tab selection Rust bridge

## Modifiche
- aggiunto l'intent Rust `select_tab` nel reducer `review_core_panel_apply_intent`
- aggiornato `CodeReviewPanelStore.selectTab` per usare il reducer Rust come path primario
- instradati a `selectTab(...)` i punti panel-side che facevano ancora assegnazioni dirette:
  - create/select chat thread
  - fallback `applyUnavailableRunError`
- mantenuto un fallback locale esplicito anche per il tab switch, coerente con la tranche precedente sugli selection intents

## Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `./scripts/build_rust_search_backend.sh`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSetSelectedSessionFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSchedulePanelSessionBindingFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSelectHistoricalFindingFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSelectTabFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadActivatesChatTab`

## Esito
- il reducer runtime Rust conosce ora anche il tab attivo selezionato localmente dal panel
- il branch findings/chat/history usa un path coerente con gli altri intent locali gia' migrati
- il fallback locale resta operativo quando il review core non e' disponibile, evitando regressioni UI durante il cutover incrementale
