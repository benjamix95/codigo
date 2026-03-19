# P2 - Gli intent di selezione del review panel erano ancora Swift-owned e non entravano nello snapshot runtime Rust

## Bug Fix Record
- Categoria: B
- Bug: il panel review usava gia' il review core Rust per run/chat lifecycle ed event reduction, ma continuava a mutare localmente in Swift `panelSessionId`, `selectedFindingId` e `selectedHistoricalFindingId`, lasciando questi intent fuori dallo snapshot runtime canonico.
- Sintomo: cambio sessione, focus del finding, focus storico e panel-session binding avvenivano con assegnazioni dirette nel `CodeReviewPanelStore`, senza passare dal boundary Rust gia' usato dal resto del runtime panel.
- Impatto: rischio di split-brain tra stato osservato dalle view e stato runtime passato ai reducer Rust; il cutover del panel restava incompleto proprio sui cambi di contesto che decidono quale review/session/detail la UI sta mostrando.
- Gravita': media, perche' tocca state management condiviso nel panel ma non altera ancora orchestration provider o patch workflow.
- Steps to reproduce:
  1. Aprire il review panel.
  2. Cambiare sessione attiva oppure aprire un finding / finding storico.
  3. Verificare che il reducer Rust non riceve alcun intent dedicato per queste transizioni locali e che il cambio di contesto vive solo nello store Swift.
- Risultato attuale: il runtime Rust governa stream e start/finish, ma non i principali intent locali di selezione del panel.
- Risultato atteso: il review core Rust deve poter ricevere e applicare gli intent di selezione panel-local, cosi' lo snapshot runtime conosce anche session binding e selezioni detail.
- Causa probabile: il primo cutover del panel ha coperto i reducer di streaming e lifecycle, ma non il sottoinsieme di intent locali considerati "solo UI".
- Scope consentito:
  - `Native/RustCore/src/review_panel_runtime/*`
  - `Native/RustCore/src/ffi/review_panel_runtime.rs`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/*`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Findings/*`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/History/*`
  - `Tests/SoloCodeAppTests/CodeReviewPanelSessionScopingTests.swift`
  - `Tests/SoloCodeAppTests/ReviewPanelChatSessionStoreTests.swift`
  - `Tests/SoloCodeAppTests/CodeReviewPanelChatPromptRoutingTests.swift`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - persistenza thread chat
  - patch workflow
  - provider creation / orchestration run
  - tool ownership MCP review/security/bughunter
- Moduli confinanti da verificare:
  - `CodeReviewPanelSessionScopingTests`
  - `ReviewPanelChatSessionStoreTests`
  - `CodeReviewPanelChatPromptRoutingTests`
  - reducer Rust `review_panel_runtime`
- Test da aggiungere o aggiornare:
  - unit test Rust sugli intent `set_selected_session`, `bind_panel_session`, `focus_finding`, `focus_historical_finding`, `clear_selected_*`
  - test app-side sul fallback locale quando il review core e' forzato off
  - smoke sul tab chat/thread switch ancora funzionante
- Strategia di fix minimo:
  - introdurre un nuovo entrypoint `review_core_panel_apply_intent`
  - estendere `ReviewPanelRuntimeStateSnapshot` con `panelSessionId`, `selectedFindingId`, `selectedHistoricalFindingId`
  - far usare a Swift il reducer Rust come path primario per questi intent
  - mantenere un fallback locale esplicito per evitare regressioni UI quando il review core non e' disponibile o il bridge non risponde
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `./scripts/build_rust_search_backend.sh`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSetSelectedSessionFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSchedulePanelSessionBindingFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSelectHistoricalFindingFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadActivatesChatTab`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelChatPromptRoutingTests`
- Commit previsto: `refactor(review-panel): route selection intents through rust runtime`

## Effetto osservato
- Il panel runtime Rust conosce ora anche:
  - session binding del panel
  - selection del finding live
  - selection del finding storico
- Swift non aggiorna piu' direttamente questi campi come unico owner; usa un boundary Rust esplicito e ricade localmente solo in caso di runtime non disponibile.
