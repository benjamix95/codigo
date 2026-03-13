# P2 - Il fallback del live board storico review era ancora posseduto da Swift

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewPanelStore+HistoryLive.swift` continuava a costruire in Swift il live board storico quando `fileLedger` era vuoto, usando worker plan activities e swarm cards.
- Sintomo: il panel review manteneva un file Swift non-UI dedicato per comporre worker/files del live board anche se il boundary Rust `review_core_panel_history_live` esisteva gia'.
- Impatto: il backlog del prefisso review restava piu' alto e la derivazione del live board non era ancora centralizzata nel core Rust.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `CodeReviewPanelStore+HistoryLive.swift`.
  2. Verificare che, in assenza di `fileLedger`, il file ricostruisca worker/files da activities e swarm cards in Swift.
  3. Notare che il file compare ancora come legacy non-UI nel conteggio del panel review.
- Risultato attuale: il live board storico usava ancora fallback Swift per i casi senza `fileLedger`.
- Risultato atteso: il core Rust deve saper derivare il live board anche da worker plans e live cards semplificati, lasciando a Swift solo la costruzione del payload.
- Causa probabile: la tranche iniziale del boundary Rust history live copriva solo `fileLedger`, lasciando il fallback transitorio nello store Swift.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store`
  - `Native/RustCore/src/review_history`
  - `Native/RustCore/src/review_panel.rs`
  - `Native/RustCore/src/ffi`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - UI della tab history
  - core review engine fuori dal live board history
  - modifiche unrelated in altri domini
- Moduli confinanti da verificare:
  - `ReviewPanelFindingsHistoryLiveBoardTests`
  - boundary `review_core_panel_history_live`
  - reducer `ReviewPanelHistoryLiveRustAdapter`
- Test da aggiungere o aggiornare:
  - test Rust sul caso `worker_plans`
  - validation review con budget gate attivo
- Strategia di fix minimo:
  - estendere il contratto `review_core_panel_history_live` con `workerPlans` e `liveCards`
  - spostare la derivazione fallback nel core Rust
  - riassorbire le due computed property in `CodeReviewPanelStore+History.swift`
  - rimuovere `CodeReviewPanelStore+HistoryLive.swift` e i riferimenti Xcode
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml review_history -- --nocapture`
  - `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+History.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PipelineJobState.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+CompletionFinalization.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+HistoryLive.swift,Native/RustCore/src/review_history/mod.rs,Native/RustCore/src/review_history/live.rs,Native/RustCore/src/review_history/live_inputs.rs,Native/RustCore/src/review_panel.rs,Native/RustCore/src/ffi/review_panel.rs,Native/RustCore/src/ffi/review_core.rs,"Solo Code.xcodeproj/project.pbxproj",scripts/validate_rust_cutover_boundary.sh`
- Commit previsto: `refactor(review): move history live fallback into rust core`

## Fix applicato
- esteso `review_core_panel_history_live` per accettare anche `workerPlans` e `liveCards`
- spostata la derivazione fallback del live board in `Native/RustCore/src/review_history/live.rs` con supporto modulare in `live_inputs.rs`
- riassorbite `historyLiveRefreshKey` e `currentHistoricalLiveRunState` in `CodeReviewPanelStore+History.swift`
- rimosso `CodeReviewPanelStore+HistoryLive.swift` dal filesystem e dal progetto Xcode

## Esito
- backlog panel review ridotto da `28` a `27`
- nessuna nuova violazione Swift non-UI
- build, test Rust e test selettivi review restano verdi
