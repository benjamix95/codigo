# 2026-03-19 - Review panel selection intents Rust bridge

## Modifiche
- esteso `ReviewPanelRuntimeStateSnapshot` lato Rust e Swift con:
  - `panelSessionId`
  - `selectedFindingId`
  - `selectedHistoricalFindingId`
- aggiunto un nuovo reducer Rust `review_core_panel_apply_intent` con supporto a:
  - `set_selected_session`
  - `bind_panel_session`
  - `focus_finding`
  - `focus_historical_finding`
  - `clear_selected_finding`
  - `clear_selected_historical_finding`
- introdotto il file Rust `Native/RustCore/src/review_panel_runtime/intents.rs`
- instradati verso il reducer Rust i path panel-side che cambiano il contesto osservato dalle view:
  - `setSelectedSession`
  - `schedulePanelSessionBinding`
  - `bindPanelRunSession`
  - `focusFinding`
  - `selectHistoricalFinding`
  - back actions findings/history
  - binding della sessione pin-nata nel chat send path
- mantenuto un fallback locale esplicito in Swift per questi intent quando il runtime Rust non e' disponibile o il bridge non risponde, per non rompere il comportamento UI durante il cutover progressivo
- aggiornati i test app-side per coprire il fallback locale e riallineato il path del review core usato dalla suite session-scoping al `build/lib` aggiornato dallo script del progetto

## Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `./scripts/build_rust_search_backend.sh`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSetSelectedSessionFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSchedulePanelSessionBindingFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSelectHistoricalFindingFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadActivatesChatTab`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelChatPromptRoutingTests`

## Esito
- il review core Rust puo' ora ricevere e applicare gli intent locali di selezione del panel
- le view findings/history non dipendono piu' solo da assegnazioni dirette per resettare o cambiare il contesto attivo
- la UI conserva un fallback locale controllato, quindi la tranche riduce ownership Swift senza introdurre regressioni immediate sul panel

## Note
- `CodeReviewPanelChatPromptRoutingTests` resta dipendente dalla disponibilita' del review core nell'ambiente di test; i casi che richiedono davvero il runtime vengono ora saltati esplicitamente quando la dylib non e' caricabile
- il crate Rust continua a emettere warning `dead_code` su alcuni campi `schema_version` e request metadata gia' esistenti; non bloccano la tranche ma restano backlog tecnico separato
