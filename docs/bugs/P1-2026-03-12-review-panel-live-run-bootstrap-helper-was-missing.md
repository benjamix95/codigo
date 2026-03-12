# P1 - Il review panel non aveva ancora un helper unico per il bootstrap dei run live

## Bug Fix Record
- Categoria: A
- Bug: `startReview(...)` e `launchTargetedFixRun(...)` condividevano ancora troppa logica di bootstrap live, ma senza un helper dedicato che centralizzasse la creazione di session state/provider e l'attivazione dello stato run.
- Sintomo: il wiring del run live era distribuito su piu' call site, rendendo piu' fragile la prossima migrazione dell'orchestration live fuori dal panel.
- Impatto: alto costo di manutenzione e rischio di drift semantico tra run standard e targeted fix.
- Gravita': alta, perche' tocca il boundary di orchestration live ancora Swift-owned.
- Steps to reproduce:
  1. Confrontare `startReview(...)` e `launchTargetedFixRun(...)`.
  2. Osservare che conversation resolution, state factory, provider factory e activation erano ancora ripetuti o parzialmente divergenti.
- Risultato attuale: manca un boundary helper unico per il run live.
- Risultato atteso: il panel deve avere un helper comune che riduca duplicazione e renda piu' semplice il futuro cutover dell'orchestration.
- Causa probabile: le tranche precedenti hanno migrato reducers e planning, ma non ancora il wiring live condiviso.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+LiveRunExecution.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Launch.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+TargetedFix.swift`
  - `Tests/SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - migrazione completa dell'orchestration live in Rust
  - UI SwiftUI
  - provider runtime semantics
- Moduli confinanti da verificare:
  - `CodeReviewPanelLiveRunExecutionTests`
  - `CodeReviewPanelSessionScopingTests`
- Test da aggiungere o aggiornare:
  - regressione helper su `panelRunConversationId`
  - regressione helper su `activatePanelRunSession`
- Strategia di fix minimo:
  - introdurre helper unico `LiveRunExecution`
  - riusare lo stesso helper per run standard e targeted fix
  - non modificare il comportamento osservabile del panel
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests`
  - build/compilazione passano; esecuzione suite ancora bloccata dal problema ambientale LaunchServices/Xcode
- Commit previsto: `refactor(review-panel): share live run bootstrap helpers`
