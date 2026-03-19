# P2 - La selezione del tab nel review panel era ancora Swift-owned fuori dal reducer runtime Rust

## Bug Fix Record
- Categoria: B
- Bug: dopo la tranche degli selection intents, il panel review continuava a cambiare `selectedTab` con assegnazioni dirette Swift in diversi punti (`selectTab`, create/select chat thread, fallback run unavailable), lasciando il cambio tab fuori dal reducer runtime Rust.
- Sintomo: il review core Rust conosceva session binding e detail selection, ma non il cambio tab esplicito originato dal panel; lo snapshot runtime non era quindi il source of truth completo per il contesto UI locale.
- Impatto: ownership ancora parziale nel layer Swift, con rischio di drift tra tab mostrato dalla UI e stato panel passato ai reducer Rust durante i passaggi findings/chat/history.
- Gravita': media.
- Steps to reproduce:
  1. Aprire il review panel.
  2. Passare manualmente tra tab oppure creare/selezionare un thread chat.
  3. Verificare che il cambio tab avviene localmente in Swift senza intent dedicato verso il runtime Rust.
- Risultato attuale: `selectedTab` non passava ancora dal boundary Rust usato per gli altri intent locali del panel.
- Risultato atteso: anche il cambio tab deve transitare nel reducer `review_core_panel_apply_intent`, con fallback locale solo se il runtime non e' disponibile.
- Causa probabile: il primo batch di selection intents aveva coperto session/detail selection ma non il cambio tab, trattato ancora come puro dettaglio UI.
- Scope consentito:
  - `Native/RustCore/src/review_panel_runtime/*`
  - `Native/RustCore/src/ffi/review_panel_runtime.rs`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/*`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Chat/*`
  - `Tests/SoloCodeAppTests/CodeReviewPanelSessionScopingTests.swift`
  - `Tests/SoloCodeAppTests/ReviewPanelChatSessionStoreTests.swift`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - patch workflow
  - MCP ownership
  - chat thread persistence
  - provider orchestration
- Moduli confinanti da verificare:
  - `CodeReviewPanelSessionScopingTests`
  - `ReviewPanelChatSessionStoreTests`
  - reducer Rust `review_panel_runtime::intents`
- Test da aggiungere o aggiornare:
  - unit test Rust `select_tab`
  - test app-side sul fallback locale di `selectTab`
  - smoke su create/select chat thread che continua ad attivare `.chat`
- Strategia di fix minimo:
  - aggiungere l'intent Rust `select_tab`
  - instradare `CodeReviewPanelStore.selectTab` verso `applyPanelIntent`
  - aggiornare i callsite che cambiavano il tab direttamente per usare `selectTab`
  - mantenere fallback locale per non rompere il panel quando il bridge Rust non risponde
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `./scripts/build_rust_search_backend.sh`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSetSelectedSessionFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSchedulePanelSessionBindingFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSelectHistoricalFindingFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSelectTabFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadActivatesChatTab`
- Commit previsto: `refactor(review-panel): route tab selection through rust runtime`

## Effetto osservato
- Il reducer Rust del panel runtime supporta ora anche `select_tab`.
- Il cambio tab non e' piu' solo un effetto collaterale Swift: passa dal boundary Rust e resta coerente con il resto dello snapshot runtime.
