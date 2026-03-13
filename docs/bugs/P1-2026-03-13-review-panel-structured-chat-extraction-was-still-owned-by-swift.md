# P1 - L'estrazione del blocco `review_findings` del panel review era ancora owned da Swift

## Bug Fix Record
- Categoria: A
- Bug: il panel Code Review estraeva e trasformava in Swift il blocco markdown `review_findings`, invece di delegare il parsing al core Rust.
- Sintomo: `CodeReviewPanelStore+ChatFindings.swift` conteneva regex, parse JSON e mapping dei finding chat nel layer app.
- Impatto: rischio di drift tra il contratto review del panel e il core Rust, con dedup/parsing non piu' governati da un source of truth unico.
- Gravita': alta, perche' tocca il boundary di ingest dei finding strutturati e la migrazione del panel fuori da Swift.
- Steps to reproduce:
  1. Pubblicare nel panel un messaggio assistant con blocco ` ```review_findings ... ``` `.
  2. Eseguire la sync verso la tab Findings.
  3. Verificare che il parsing del blocco veniva ancora eseguito localmente nel panel store.
- Risultato attuale: il panel usava codice Swift locale per regex, decode e mapping dei finding.
- Risultato atteso: il parsing del blocco deve vivere nel core Rust; Swift deve solo applicare il payload risultante.
- Causa probabile: la migrazione precedente aveva spostato il merge/dedup, ma non l'estrazione del contenuto strutturato dalla chat.
- Scope consentito:
  - `Native/RustCore/src/review_panel.rs`
  - `Native/RustCore/src/ffi/review_panel.rs`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatFindings.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustChatFindings.swift`
  - documentazione `docs/bugs`, `docs/changelog`, `docs/migration`
- Non-scope:
  - rendering UI della chat
  - workflow patch/apply
  - verified findings query/status lato MCP
- Moduli confinanti da verificare:
  - `CodeReviewPanelSessionScopingTests`
  - `review_panel` Rust unit tests
- Test da aggiungere o aggiornare:
  - test Rust per blocco valido e payload malformato
  - verifica Swift del sync chat -> findings sul path panel
- Strategia di fix minimo:
  - introdurre entrypoint FFI dedicato `review_core_panel_chat_extract`
  - spostare in Rust parse blocco, mapping finding e merge con count inserimenti
  - ridurre il panel store a solo adapter/apply state
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests -only-testing:SoloCodeAppTests/ReviewPanelLifecycleE2ETests`
- Commit previsto: `refactor(review-panel): move structured chat extraction into rust core`
