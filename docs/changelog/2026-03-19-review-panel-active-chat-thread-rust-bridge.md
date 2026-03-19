# 2026-03-19 - Review panel active chat thread Rust bridge

## Modifiche
- esteso `ReviewPanelRuntimeStateSnapshot` lato Rust e Swift con `activeChatThreadId`
- aggiunti nel reducer Rust gli intent:
  - `set_active_chat_thread`
  - `clear_active_chat_thread`
- instradati verso il reducer Rust i callsite panel-side che cambiavano il thread attivo:
  - bootstrap del thread implicito in `ensureActiveChatThread()`
  - `createNewChatThread(...)`
  - `selectChatThread(...)`
  - `applyChatConversationState(_:)`
  - reconcile iniziale del conversation cached nel bootstrap dello store
- mantenuto un fallback locale esplicito quando il review core non e' disponibile o il bridge dell’intent fallisce

## Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `./scripts/build_rust_search_backend.sh`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadActivatesChatTab -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadSyncsRuntimeSnapshotWhenRustAvailable -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadFallsBackLocallyWhenRustUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests/testApplyChatConversationStateReconcilesActiveThreadIntoRuntimeSnapshot`

## Esito
- il runtime Rust del panel conosce ora anche il thread chat attivo
- la persistenza dei thread resta in Swift, ma la selezione attiva non e' piu' solo Swift-owned
- i test app-side mirati passano; i casi che dipendono dalla disponibilita' del review core vengono saltati esplicitamente quando il runtime non e' caricabile nell’ambiente di test
