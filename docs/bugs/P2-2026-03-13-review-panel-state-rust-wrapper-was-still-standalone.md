# P2 - Il wrapper Rust dello state panel review restava ancora in un file Swift dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewPanelStore+RustPanelState.swift` continuava a esistere come file Swift non-UI separato pur contenendo solo bridge e DTO di supporto per runtime/reducer gia' in Rust.
- Sintomo: il panel review manteneva un file legacy dedicato per derived state e runtime state snapshot, anche se la logica vera era gia' nel core Rust.
- Impatto: il backlog del prefisso review restava piu' alto del necessario e il boundary Swift del panel era ancora frammentato.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `CodeReviewPanelStore+RustPanelState.swift`.
  2. Verificare che esponga solo adapter/reducer DTO e mutazioni di runtime state basate su `ReviewCoreBridge`.
  3. Notare che il file compare ancora nel conteggio legacy del panel review.
- Risultato attuale: il wrapper `RustPanelState` era ancora un file Swift non-UI separato.
- Risultato atteso: il boundary residuo verso Rust deve vivere in file store gia' esistenti, senza wrapper dedicati superflui.
- Causa probabile: tranche precedenti avevano portato in Rust la logica di panel state, ma non avevano ancora riassorbito il wrapper Swift restante.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - nuove API Rust
  - cambi di comportamento del panel
  - UI
- Moduli confinanti da verificare:
  - `CodeReviewPanelStore+PipelineJobState.swift`
  - `CodeReviewPanelStore+SnapshotMutation.swift`
  - `CodeReviewPanelStore+Summary.swift`
  - `CodeReviewPanelStore+ChatSession.swift`
  - `CodeReviewPanelStore+LiveRunExecution.swift`
- Test da aggiungere o aggiornare:
  - validation review con budget gate attivo
  - suite selettiva `SoloCodeAppTests` eseguita da `scripts/solocode-validate`
- Strategia di fix minimo:
  - spostare adapter e DTO del reducer panel in `PipelineJobState`
  - spostare runtime snapshot/apply/chat-finish in `SnapshotMutation`
  - spostare helper `String`/`Dictionary` in `Summary`
  - rimuovere il file dedicato e i riferimenti Xcode
- Verifica post-fix:
  - `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PipelineJobState.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+SnapshotMutation.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Summary.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustPanelState.swift,"Solo Code.xcodeproj/project.pbxproj",scripts/validate_rust_cutover_boundary.sh`
- Commit previsto: `refactor(review): merge rust panel state bridge into existing store files`

## Fix applicato
- adapter e DTO del reducer panel spostati in `CodeReviewPanelStore+PipelineJobState.swift`
- runtime state snapshot/apply/chat finish spostati in `CodeReviewPanelStore+SnapshotMutation.swift`
- helper `reviewToolStatus`, `reviewPanelWarmState` e `findingSeverityCounts` spostati in `CodeReviewPanelStore+Summary.swift`
- rimosso `CodeReviewPanelStore+RustPanelState.swift` dal filesystem e dal progetto Xcode

## Esito
- backlog panel review ridotto da `31` a `30`
- nessuna nuova violazione Swift non-UI
- build e test selettivi review restano verdi
