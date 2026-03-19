# P2 - La selezione del thread chat attivo nel review panel era ancora Swift-owned

## Bug Fix Record
- Categoria: B
- Bug: `activeChatThreadId` nel review panel restava mutato direttamente in Swift, quindi il runtime Rust non conosceva quale thread chat fosse attivo.
- Sintomo: `createNewChatThread(...)`, `selectChatThread(...)`, `ensureActiveChatThread()` e `applyChatConversationState(...)` aggiornano `activeChatThreadId` localmente senza passare dal reducer `review_core_panel_apply_intent`.
- Impatto: lo snapshot runtime Rust del panel restava incompleto proprio sul contesto chat locale; il panel continuava ad avere split-brain tra store Swift e runtime Rust.
- Gravita': media.
- Steps to reproduce:
  1. Creare o selezionare un thread chat nel review panel.
  2. Verificare che il panel aggiorna `activeChatThreadId` localmente.
  3. Osservare che il reducer Rust non riceve alcun intent dedicato sul thread attivo.
- Risultato attuale: `activeChatThreadId` vive solo nel panel/store Swift.
- Risultato atteso: anche il thread attivo deve entrare nello snapshot runtime Rust tramite intent espliciti.
- Causa probabile: le tranche precedenti hanno coperto session binding, selezione finding e tab selection, ma non il contesto `activeChatThreadId`.
- Scope consentito:
  - `Native/RustCore/src/review_panel_runtime/*`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/*`
  - `Tests/SoloCodeAppTests/ReviewPanelChatSessionStoreTests.swift`
  - `Tests/SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests.swift`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - persistenza `ReviewPanelChatSessionStore`
  - orchestration run/chat
  - patch workflow
  - MCP ownership
- Moduli confinanti da verificare:
  - `ReviewPanelChatSessionStoreTests`
  - `CodeReviewPanelChatStateDeferralTests`
  - reducer Rust `review_panel_runtime::intents`
- Test da aggiungere o aggiornare:
  - test Rust su `set_active_chat_thread` e `clear_active_chat_thread`
  - test app-side su create/select thread con fallback locale
  - test di reconcile da `conversation.activeThreadId`
- Strategia di fix minimo:
  - estendere `ReviewPanelRuntimeStateSnapshot` con `activeChatThreadId`
  - aggiungere intent Rust `set_active_chat_thread` e `clear_active_chat_thread`
  - instradare create/select/ensure/applyConversation verso il reducer Rust
  - mantenere fallback locale se il review core non e' disponibile
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `./scripts/build_rust_search_backend.sh`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadActivatesChatTab -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadSyncsRuntimeSnapshotWhenRustAvailable -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadFallsBackLocallyWhenRustUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests/testApplyChatConversationStateReconcilesActiveThreadIntoRuntimeSnapshot`
- Commit previsto: `refactor(review-panel): route active chat thread through rust runtime`

## Effetto osservato
- Il reducer Rust del panel runtime conosce ora anche `activeChatThreadId`.
- Swift continua a possedere la persistenza thread/messages, ma non e' piu' l’unico owner della selezione del thread attivo.
