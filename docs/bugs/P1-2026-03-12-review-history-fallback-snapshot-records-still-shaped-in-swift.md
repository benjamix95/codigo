# P1 - I record storici fallback derivati dagli snapshot review erano ancora costruiti nel panel Swift

## Bug Fix Record
- Categoria: A
- Bug: il path `fallbackHistoricalFindings()` del review panel costruiva ancora in Swift i `HistoricalFindingRecord` partendo dagli snapshot review, con mapping di severita', stato, patch apply, verdict e timeline eventi.
- Sintomo: anche con review core Rust attivo, la history del panel conservava un secondo motore Swift per la derivazione dei record storici da snapshot.
- Impatto: rischio di drift tra snapshot canonico Rust e storico panel, soprattutto su `status`, `resumeEligible`, `closedReason`, timeline eventi e sorting.
- Gravita': alta, perche' tocca la rappresentazione persistente/storica di finding review.
- Steps to reproduce:
  1. Aprire il tab History con storico DB vuoto o incompleto.
  2. Lasciare che il panel ricada sul fallback costruito dagli snapshot review.
  3. Seguire il path `CodeReviewPanelStore+History.swift` e osservare che la trasformazione finding/patch -> `HistoricalFindingRecord` e' ancora interamente Swift-owned.
- Risultato attuale: il fallback snapshot-history veniva materializzato da helper Swift locali.
- Risultato atteso: il core Rust deve derivare i record storici dagli snapshot; Swift deve solo aggregare/richiedere shape e presentare il risultato.
- Causa probabile: la migrazione precedente ha coperto merge/history shape e live board, ma non la costruzione dei record fallback da snapshot review.
- Scope consentito:
  - `Native/RustCore/src/review_history/*`
  - `Native/RustCore/src/ffi/*`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+History.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustHistoricalFindings.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - UI SwiftUI del tab History
  - fallback live basato su `TaskActivityStore`
  - rimozione completa di tutti i path Swift del panel
- Moduli confinanti da verificare:
  - `ReviewPanelFindingsHistoryTests`
  - `HistoricalFindingsQueryService`
  - `review_core_reduce_panel_state`
  - `review_core_shape_historical_findings`
- Test da aggiungere o aggiornare:
  - test Rust su derivazione history da snapshot
  - build/test mirato su `ReviewPanelFindingsHistoryTests` e `ReviewPanelFindingsHistoryLiveBoardTests`
- Strategia di fix minimo:
  - introdurre un reducer Rust `derive_historical_findings_from_snapshot`
  - aggiungere adapter Swift per invocare il reducer snapshot-by-snapshot e il shape finale Rust
  - mantenere un legacy fallback locale solo come safety net se il bridge Rust non e' disponibile
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryLiveBoardTests`
  - la compilazione passa; l'esecuzione suite si ferma in ambiente su launch della app di test (`Failed to send resume to target process`)
- Commit previsto: `refactor(review-panel): derive snapshot history records in rust`
