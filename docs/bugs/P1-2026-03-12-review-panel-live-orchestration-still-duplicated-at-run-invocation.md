# P1 - L’invocazione del run live nel review panel restava duplicata tra launch standard e targeted fix

## Bug Fix Record
- Categoria: A
- Bug: dopo l’introduzione degli helper bootstrap, `startReview(...)` e `launchTargetedFixRun(...)` duplicavano ancora parte dell’invocazione del run live: attivazione stato panel, wiring `coordinator.runReview(...)` e gestione base `complete/fail`.
- Sintomo: l’orchestration live non era ancora davvero centralizzata; due call site continuavano ad avere callback e transizioni quasi identiche.
- Impatto: rischio di drift nel comportamento live del panel e maggiore difficolta' nel prossimo cutover di orchestration fuori da Swift.
- Gravita': alta, perche' tocca il boundary live rimasto nel panel.
- Steps to reproduce:
  1. Confrontare `startReview(...)` e `launchTargetedFixRun(...)`.
  2. Osservare duplicazione su `activatePanelRunSession`, `coordinator.runReview`, `complete/fail` del run.
- Risultato attuale: esisteva ancora boilerplate live duplicato.
- Risultato atteso: il panel deve avere un helper unico anche per l’invocazione del run e le transizioni base del lifecycle live.
- Causa probabile: le tranche precedenti hanno consolidato bootstrap e planning, ma non ancora il punto di invocazione effettiva del run.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+LiveRunExecution.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Launch.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+TargetedFix.swift`
  - `Tests/SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests.swift`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - migrazione totale dell’orchestration live in Rust
  - UI SwiftUI
  - semantics provider-side della review
- Moduli confinanti da verificare:
  - `CodeReviewPanelLiveRunExecutionTests`
- Test da aggiungere o aggiornare:
  - regressione helper su `completePanelRun`
  - regressione helper su `failPanelRun`
- Strategia di fix minimo:
  - centralizzare in `LiveRunExecution` anche l’invocazione base del run live
  - far riusare ai due call site lo stesso helper
  - mantenere invariato il comportamento osservabile del panel
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests`
  - build/compilazione passano; il run resta esposto al problema LaunchServices/Xcode gia' noto
- Commit previsto: `refactor(review-panel): centralize live run execution helpers`
