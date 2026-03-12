# P1 - Il live board storico del review panel derivato dallo snapshot era ancora modellato in Swift

## Bug Fix Record
- Categoria: A
- Bug: il pannello history derivava worker/file board dai `phaseLedger` e `fileLedger` dello snapshot direttamente in Swift, anche se il core Rust era gia' owner dello stato canonico review.
- Sintomo: il live board storico usava ancora logica Swift per grouping, severity sorting e mapping degli status del ledger, lasciando il boundary review panel incompleto rispetto alla migrazione Rust.
- Impatto: rischio di drift semantico tra snapshot canonico Rust e presentazione panel, soprattutto su ordinamento file/worker e mapping degli status terminali.
- Gravita': alta, perche' tocca uno snapshot review canonico condiviso dal panel.
- Steps to reproduce:
  1. Aprire il review panel su una sessione con `fileLedger`.
  2. Osservare il live board storico nel tab History.
  3. Seguire il path `CodeReviewPanelStore+HistoryLive` e verificare che grouping e ordinamento siano ancora decisi in Swift.
- Risultato attuale: il panel usava lo snapshot Rust ma derivava il board storico via helper Swift locali.
- Risultato atteso: quando il live board puo' essere derivato solo dallo snapshot, il core Rust deve produrre worker/file state e Swift deve limitarsi a fare da adapter.
- Causa probabile: la migrazione precedente ha coperto `panel derived state` generale, ma non il sottopath specifico della history live board.
- Scope consentito:
  - `Native/RustCore/src/review_history.rs`
  - `Native/RustCore/src/ffi/review_core.rs`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+HistoryLive.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustHistoryLiveState.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - fallback live basato su `TaskActivityStore`
  - refactor completo del panel history
  - UI SwiftUI del tab History
- Moduli confinanti da verificare:
  - `ReviewPanelFindingsHistoryLiveBoardTests`
  - `review_history` Rust tests
  - `review_core_reduce_panel_state`
- Test da aggiungere o aggiornare:
  - unit test Rust su `derive_history_live_state`
  - build/test mirato del panel history live board
- Strategia di fix minimo:
  - introdurre una nuova operazione Rust `derive_history_live_state`
  - aggiungere adapter Swift stretto per convertire il payload Rust in `ReviewHistoricalLiveBoardState`
  - usare il path Rust solo quando esiste `fileLedger`; mantenere il fallback activity-driven in Swift
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryLiveBoardTests`
  - il build passa; il run dei test e' bloccato in ambiente da crash/assertion LaunchServices di Xcode
- Commit previsto: `refactor(review-panel): derive history live board snapshot state in rust`
