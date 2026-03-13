# P1 - Il runtime live del review panel era ancora orchestrato in Swift

## Bug Fix Record
- Categoria: A - Critico
- Bug: il panel review manteneva in Swift il lifecycle live di run/chat, incluse transizioni `isRunning`, finalizzazione dell'output, split della response bubble e chiusura coerente su complete/cancel/error.
- Sintomo: `ReviewPanelCoordinator`, `CodeReviewPanelStore+LiveRunExecution`, `CodeReviewPanelStore+ActionOutput` e `CodeReviewPanelStore+ChatSession` decidevano ancora business logic locale sul flusso streaming.
- Impatto: ownership duplicata tra panel Swift e core Rust, rischio di drift tra session state canonico e comportamento osservabile del panel review.
- Gravita': alta
- Steps to reproduce:
  1. Avviare un run review o una chat del panel con stream multi-evento (`textDelta`, `textReplace`, `raw`, `completed`, `error`).
  2. Osservare che il panel mutava localmente stato, response bubble e finalizzazione senza passare da un reducer Rust dedicato.
  3. Disabilitare il core Rust e notare che il panel continuava ad avere branching live locale Swift.
- Risultato attuale: il runtime live del panel deve essere Rust-owned; Swift deve restare adapter di task, cancellazione e applicazione mutazioni.
- Risultato atteso: stream review/chat ridotti via reducer Rust (`review_core_panel_run_*`, `review_core_panel_chat_*`) e nessun fallback Swift di business logic.
- Causa probabile: tranche precedenti avevano già migrato panel state/history/chat findings, ma non il path live runtime del panel.
- Scope consentito:
  - `Native/RustCore/src/review_panel_runtime/*`
  - `Native/RustCore/src/ffi/review_panel_runtime.rs`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Coordinator/ReviewPanelCoordinator.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+LiveRunExecution.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ActionOutput.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatSession.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustPanelState.swift`
  - test panel runtime e validation mapping
- Non-scope:
  - migrazione completa provider/network transport a Rust
  - persistenza `ReviewPanelChatSessionStore`
  - bridge unificato `AppCoreBridge`
- Moduli confinanti da verificare:
  - `ReviewCoreBridge`
  - `RustSearchFFIClient`
  - `TaskActivityStore`
  - `ReviewSessionRegistry`
- Test da aggiungere o aggiornare:
  - unit test Rust su reducer `run/chat start/reduce/finish`
  - test Swift panel runtime con skip esplicito se il core Rust non e' disponibile nel test host
  - validazione mirata del panel runtime senza fallback sull'intero bundle `CoderEngineTests`
- Strategia di fix minimo:
  - introdurre un modulo Rust dedicato al runtime live del panel
  - ridurre `ReviewPanelCoordinator` a task driver
  - spostare nel reducer Rust la semantica di output/finalizzazione
  - allineare il path del dylib Rust nei test panel al workspace Cargo (`Native/target/debug`)
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml review_panel_runtime -- --nocapture`
  - `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files <slice>`
- Commit previsto: `refactor(review-panel): route live runtime through rust`
