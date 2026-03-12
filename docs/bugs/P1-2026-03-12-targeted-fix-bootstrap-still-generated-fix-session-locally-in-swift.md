# P1 - Il bootstrap del targeted fix generava ancora `fixSessionId` e config localmente in Swift

## Bug Fix Record
- Categoria: A
- Bug: `launchTargetedFixRun(...)` costruiva ancora localmente `fixSessionId` e la config iniziale del run targeted-fix, invece di usare il planner Rust gia' introdotto per il launch standard.
- Sintomo: il panel aveva ancora due path diversi di bootstrap review: uno Rust-backed per `startReview`, uno locale Swift per `targeted fix`.
- Impatto: rischio di drift tra launch standard e targeted fix su normalizzazione `sessionId`, prefissi, e config iniziale della sessione.
- Gravita': alta, perche' tocca una variante del launch review nel panel.
- Steps to reproduce:
  1. Avviare un targeted fix dal panel.
  2. Seguire `launchTargetedFixRun(...)`.
  3. Osservare che `fixSessionId` e config venivano ancora costruiti in-line da Swift.
- Risultato attuale: targeted-fix bootstrap non riusava il planning Rust.
- Risultato atteso: targeted-fix deve usare lo stesso planner Rust del launch standard, con `session_prefix` derivato dalla sessione sorgente.
- Causa probabile: la tranche precedente ha coperto il launch standard ma non il bootstrap del targeted fix.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+TargetedFix.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustLaunchPlanning.swift`
  - `Tests/SoloCodeAppTests/CodeReviewPanelSessionScopingTests.swift`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - orchestration completa live
  - provider/runtime execution
  - UI SwiftUI
- Moduli confinanti da verificare:
  - `CodeReviewPanelSessionScopingTests`
  - planner Rust `start`
- Test da aggiungere o aggiornare:
  - test panel su `planPanelTargetedFixLaunch(sourceSnapshot:)`
- Strategia di fix minimo:
  - riusare il planner Rust con `session_prefix = "<sourceSessionId>-fix"`
  - eliminare la generazione locale di `fixSessionId`
  - mantenere invariato il resto del targeted-fix runtime
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests`
  - build e compilazione passano; esecuzione suite ancora soggetta al problema LaunchServices/Xcode dell'ambiente
- Commit previsto: `refactor(review-panel): plan targeted fix bootstrap through rust`
