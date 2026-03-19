# P1 - Il panel review ricostruiva ancora in Swift lo snapshot dei findings estratti dalla chat

## Bug Fix Record
- Categoria: B
- Bug: [CodeReviewPanelStore+ChatFindings.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+ChatFindings.swift) ricostruiva ancora in Swift findings, timeline events e outcome dopo `review_core_panel_chat_extract`.
- Sintomo:
  - merge locale dei findings estratti dalla chat
  - costruzione locale degli eventi `findingAdded`
  - ricostruzione locale di `outcome`
- Impatto: il panel runtime manteneva logica di dominio Swift in un path che dovrebbe ormai ingerire snapshot canonici dal core Rust.
- Gravita': alta, perche' tocca coerenza tra timeline panel, session snapshot e outcome derivato.
- Steps to reproduce:
  1. Aprire [CodeReviewPanelStore+ChatFindings.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+ChatFindings.swift).
  2. Cercare `syncStructuredFindingsFromChatResponse(...)`.
  3. Verificare che findings, events e outcome vengano ancora ricostruiti localmente dopo l'estrazione Rust.
- Risultato attuale: il panel non ingeriva ancora uno snapshot canonico opzionale nel response di `review_core_panel_chat_extract`.
- Risultato atteso: il core Rust deve poter restituire uno snapshot aggiornato gia' coerente; Swift deve preferirlo e mantenere solo un fallback compatibile se il payload canonico manca.
- Causa probabile: il boundary `review_core_panel_chat_extract` era rimasto limitato a `findings/insertedCount/extractedCount`, lasciando al panel la riduzione finale dello snapshot.
- Scope consentito:
  - [CodeReviewPanelStore+ChatFindings.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+ChatFindings.swift)
  - [review_panel.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_panel.rs)
  - [review_panel.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_panel.rs)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - command mutator review
  - patch workflow
  - panel patch execution
- Moduli confinanti da verificare:
  - `CodeReviewPanelSessionScopingTests`
  - boundary `review_core_panel_chat_extract`
  - strict cutover gate review
- Test da aggiungere o aggiornare:
  - smoke su `testStructuredChatFindingsSyncsIntoFindingsTimelineAndDeduplicates`
- Strategia di fix minimo:
  - estendere il request/response del boundary Rust con `snapshot`
  - costruire in Rust uno snapshot canonico opzionale con findings, events e outcome aggiornati
  - far preferire a Swift quello snapshot, mantenendo solo un fallback compatibile se il payload manca
- Verifica post-fix:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testStructuredChatFindingsSyncsIntoFindingsTimelineAndDeduplicates`
  - `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+ChatFindings.swift --format text`
- Commit previsto: `refactor(review-panel): prefer canonical chat finding snapshots`

## Effetto osservato
- Il panel puo' ingerire direttamente uno snapshot canonico dal core Rust nel path di estrazione findings da chat.
- Se il payload canonico manca, il panel mantiene il fallback locale per non rompere il contratto osservabile esistente.
