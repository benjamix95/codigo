# P2 - Il panel review manteneva ancora prompt builder Swift e presentation model fuori dal perimetro UI/Rust corretto

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: il panel `CodeReview` manteneva ancora in Swift non-UI sia il prompt builder del coordinator sia due file di presentation model collocati fuori dal perimetro `Views/**`.
- Sintomo: `ReviewPanelCoordinator+Prompts.swift` restava un file di business logic Swift nel panel, mentre `CodeReviewPanelModels.swift` e `ReviewPanelChatModels.swift` venivano conteggiati come legacy non-UI pur descrivendo tab, mode picker, stato di presentazione e modelli chat del rendering.
- Impatto: il dominio review restava gonfiato da debito Swift non-UI evitabile; inoltre il prompt building non beneficiava del runtime Rust gia' usato per il resto del panel.
- Gravita': media
- Steps to reproduce:
  1. Eseguire l'audit review strict del 2026-03-16.
  2. Osservare che il prefisso `App/SoloCodeApp/Sources/Panels/CodeReview` conteggia ancora prompt builder e model file nel backlog non-UI.
  3. Verificare che `ReviewPanelCoordinator+Prompts.swift` costruisce prompt interamente in Swift.
- Risultato attuale: il prompt builder del panel viene servito da `Native/RustCore`, mentre i model file puramente presentation-oriented sono collocati sotto `Views/Shared` e rientrano nell'allowlist UI.
- Risultato atteso: il panel mantiene in Swift solo rendering e presentation models vicini alle view; la logica di prompt building resta nel runtime Rust.
- Causa probabile: le tranche precedenti avevano gia' spostato run state, history e launch planning in Rust, ma il prompt builder del coordinator e i model file UI erano rimasti nel vecchio albero del panel.
- Scope consentito:
  - `Native/RustCore/src/review_panel_runtime/*`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Coordinator/*`
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/ReviewCommandRustBridge.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Shared/*`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - migrazione completa dello store panel
  - bootstrap review command loop
  - engine `CodeReview` e `VerifiedFindingsCore`
  - handler MCP review
- Moduli confinanti da verificare:
  - runtime prompt review in Rust
  - coordinator panel lato app
  - prompt tests del panel
  - riferimenti file dentro progetto Xcode
- Test da aggiungere o aggiornare:
  - unit test Rust per prompt `combined`, `branch_review`, `chat_context`
  - regression test Swift gia' esistenti del panel prompt/chat
- Strategia di fix minimo:
  - aggiungere un builder prompt Rust dedicato nel runtime review panel
  - usare il bridge review esistente per richiamarlo da Swift
  - mantenere fallback locale compatto per il caso in cui il bridge Rust sia disabilitato nei test
  - ricollocare i model file presentation-only sotto `Views/Shared`
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests -only-testing:SoloCodeAppTests/ReviewPanelChatStructuredContentTests`
  - audit review strict con conteggio panel ridotto
- Commit previsto: `fix(review): move panel prompts into rust runtime`

## Effetto osservato
- review strict prima: `72` file Swift non-UI legacy
- review strict dopo: `69` file Swift non-UI legacy
- riduzione panel-side:
  - `App/SoloCodeApp/Sources/Panels/CodeReview`: da `19` a `16`
