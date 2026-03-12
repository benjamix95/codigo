# P1 - Il bootstrap live del review panel era duplicato tra launch standard e targeted fix

## Bug Fix Record
- Categoria: A
- Bug: `startReview(...)` e `launchTargetedFixRun(...)` costruivano ancora in Swift gli stessi pezzi di bootstrap live: risoluzione `conversationId`, creazione `CodeReviewSessionState`, creazione provider e attivazione stato run nel panel.
- Sintomo: due path live separati nel panel mantenevano wiring quasi identico, aumentando il rischio di drift ogni volta che il bootstrap veniva irrigidito o migrato.
- Impatto: maggiore fragilita' della migrazione del boundary live, perche' il prossimo passo verso un adapter piu' sottile doveva essere fatto in due punti diversi.
- Gravita': alta, perche' tocca il bootstrap del run review nel panel.
- Steps to reproduce:
  1. Confrontare `startReview(...)` e `launchTargetedFixRun(...)`.
  2. Osservare duplicazione su conversation resolution, session state factory, provider factory e run activation.
- Risultato attuale: bootstrap live duplicato e piu' difficile da migrare/validare.
- Risultato atteso: un helper comune del panel deve possedere il bootstrap live, lasciando ai call site solo i parametri specifici.
- Causa probabile: il lavoro precedente si e' concentrato sulla migrazione Rust dei reducers, lasciando il wiring live duplicato in Swift.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+LiveRunExecution.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Launch.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+TargetedFix.swift`
  - `Tests/SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - orchestration completa via Rust
  - provider/runtime execution semantics
  - UI SwiftUI
- Moduli confinanti da verificare:
  - `CodeReviewPanelLiveRunExecutionTests`
  - `CodeReviewPanelSessionScopingTests`
- Test da aggiungere o aggiornare:
  - regressione helper su `panelRunConversationId(...)`
  - regressione helper su `activatePanelRunSession(...)`
- Strategia di fix minimo:
  - introdurre helper comune `LiveRunExecution`
  - far riusare ai due path bootstrap lo stesso wiring minimo
  - non cambiare il comportamento osservabile del panel
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests`
  - build/compilazione passano; il run resta soggetto ai problemi ambientali LaunchServices/Xcode della sessione
- Commit previsto: `refactor(review-panel): share live run bootstrap helpers`
