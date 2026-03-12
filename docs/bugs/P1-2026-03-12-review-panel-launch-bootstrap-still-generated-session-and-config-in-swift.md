# P1 - Il bootstrap di launch del review panel continuava a generare `sessionId` e config localmente in Swift

## Bug Fix Record
- Categoria: A
- Bug: `CodeReviewPanelStore+Launch.swift` costruiva ancora in Swift sia il `sessionId` sia la `SessionConfig` iniziale del run review, anche se il core Rust aveva gia' un planner per `start/configure`.
- Sintomo: il panel manteneva una seconda logica di bootstrap sessione rispetto al command boundary Rust.
- Impatto: rischio di drift tra panel launch e command loop su sanitizzazione `sessionId`, backend selection e normalizzazione della config iniziale.
- Gravita': alta, perche' tocca il bootstrap del run review e la prevedibilita' della sessione.
- Steps to reproduce:
  1. Avviare una review dal panel con mode/backend custom.
  2. Seguire il path `startReview(...)`.
  3. Osservare che `sessionId` e `SessionConfig` vengono ancora costruiti da helper Swift locali.
- Risultato attuale: il panel generava localmente session bootstrap e il planner Rust non veniva usato.
- Risultato atteso: il panel deve usare il planner Rust per ottenere `sessionId` e config iniziale, lasciando a Swift solo provider wiring e UI lifecycle.
- Causa probabile: il planner Rust era nato per il command loop e non era ancora stato riusato dal panel.
- Scope consentito:
  - `Native/RustCore/src/review_command/planner.rs`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Launch.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustLaunchPlanning.swift`
  - `Tests/SoloCodeAppTests/CodeReviewPanelSessionScopingTests.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - provider/runtime execution
  - UI del panel
  - orchestration live della review
- Moduli confinanti da verificare:
  - `review_command::planner`
  - `CodeReviewPanelSessionScopingTests`
- Test da aggiungere o aggiornare:
  - test Rust su generazione `sessionId` prefissato quando manca `session_id`
  - test panel su uso del planner Rust per prefix/config
- Strategia di fix minimo:
  - estendere il planner Rust per generare `sessionId` univoco con `session_prefix`
  - introdurre adapter Swift stretto per `start`
  - rimuovere dal panel la costruzione locale di `sessionId` e `SessionConfig`
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests`
  - build e compilazione passano; esecuzione suite ancora bloccata in ambiente da LaunchServices/Xcode
- Commit previsto: `refactor(review-panel): plan launch bootstrap through rust`
