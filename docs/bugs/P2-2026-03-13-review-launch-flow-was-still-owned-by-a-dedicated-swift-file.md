# P2 - Il flusso launch review era ancora posseduto da un file Swift dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewPanelStore+Launch.swift` continuava a concentrare in un file Swift legacy dedicato il flusso di avvio review, rerun, quick commands e mutation action base del panel.
- Sintomo: il panel review manteneva un file non-UI separato per launch/orchestration anche dopo la migrazione dei bridge Rust principali.
- Impatto: il backlog del prefisso review restava piu' alto e la logica di launch non era ancora distribuita nei file store gia' esistenti che ne possiedono il contesto operativo.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `CodeReviewPanelStore+Launch.swift`.
  2. Verificare che contenga start/rerun/quick command/cancel review, mutation action e helper di prompt/timer.
  3. Notare che il file compare ancora come legacy non-UI nel conteggio del panel review.
- Risultato attuale: il launch flow review restava in un file Swift dedicato.
- Risultato atteso: il launch flow va assorbito nei file store gia' esistenti piu' vicini al comportamento, senza nuovi file Swift non-UI.
- Causa probabile: tranche precedenti avevano drenato wrapper e bridge Rust-backed, ma non avevano ancora riassorbito il file di orchestrazione del launch panel.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - nuove API Rust
  - cambi UI
  - modifiche al core review lato engine
- Moduli confinanti da verificare:
  - `CodeReviewPanelStore+LiveRunExecution.swift`
  - `CodeReviewPanelStore+CompletionFinalization.swift`
  - `CodeReviewPanelStore+TargetedFix.swift`
  - `CodeReviewPanelView.swift`
- Test da aggiungere o aggiornare:
  - validation review con budget gate attivo
  - targeted tests `SoloCodeAppTests` eseguiti da `scripts/solocode-validate`
- Strategia di fix minimo:
  - spostare avvio/cancel review in `LiveRunExecution`
  - spostare mutation action e timer in `CompletionFinalization`
  - spostare rerun/quick command/prompt helpers in `TargetedFix`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+LiveRunExecution.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+CompletionFinalization.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+TargetedFix.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Launch.swift,"Solo Code.xcodeproj/project.pbxproj",scripts/validate_rust_cutover_boundary.sh`
- Commit previsto: `refactor(review): distribute launch flow into existing store files`

## Fix applicato
- `startReview`, `consumePendingLaunchRequestIfNeeded` e `cancelReview` spostati in `CodeReviewPanelStore+LiveRunExecution.swift`
- `applyFix`, `dismissFinding`, `applyAllFixes`, `dismissAll` e `freezeTimer` spostati in `CodeReviewPanelStore+CompletionFinalization.swift`
- `rerunSession`, `runQuickCommand`, `buildPrompt` e `reviewInvocationLabel` spostati in `CodeReviewPanelStore+TargetedFix.swift`
- rimosso `CodeReviewPanelStore+Launch.swift` dal filesystem e dal progetto Xcode

## Esito
- backlog panel review ridotto da `30` a `29`
- nessuna nuova violazione Swift non-UI
- build e test selettivi review restano verdi
