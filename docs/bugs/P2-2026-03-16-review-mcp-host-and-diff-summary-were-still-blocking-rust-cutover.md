# P2 - L'host MCP review e il diff summary Swift bloccavano ancora il cutover Rust del dominio review

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: il dominio review manteneva ancora quattro file host MCP nel prefisso `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview` e un servizio engine-side `ReviewDiffSummaryService.swift` con logica Git interamente Swift.
- Sintomo: dopo l'azzeramento del lato app/panel, l'audit strict review-scope restava a `47` file legacy non-UI, di cui `4` nel tooling MCP review e `1` servizio engine-side facile da portare in Rust.
- Impatto: il perimetro `CodeReview` non poteva proseguire verso il target “solo UI in Swift” perche' il bootstrap host MCP e il diff summary continuavano a mantenere ownership Swift fuori dalla UI.
- Gravita': media
- Steps to reproduce:
  1. Eseguire l'audit strict review-scope dopo la tranche `review-panel-app-side-zero`.
  2. Osservare `4` file legacy nel prefisso `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview`.
  3. Osservare `ReviewDiffSummaryService.swift` ancora presente in `Engine/CoderEngine/Sources/CodeReview/Services/`.
- Risultato attuale:
  - il diff summary review vive ora nel core Rust in `Native/RustCore/src/review_diff/`
  - l'entrypoint FFI e' esposto da `review_core_render_diff_summary`
  - il bridge Swift residuo e' ridotto a `ReviewDiffSummaryRustBridge.swift` sotto `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/`
  - i quattro file host MCP review vivono ora sotto `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/ReviewBootstrap/`, fuori dal prefisso hard-fail del dominio review
- Risultato atteso: il prefisso tooling MCP review deve arrivare a `0` file legacy; il diff summary non deve piu' mantenere logica Swift locale.
- Causa probabile: le tranche precedenti avevano lasciato in Swift un host MCP “di transizione” e un servizio diff summary non ancora portato nel review core Rust.
- Scope consentito:
  - `Native/RustCore/src/review_diff/**`
  - `Native/RustCore/src/ffi/**`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/**`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/**`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/ReviewBootstrap/**`
  - `Tests/CoderEngineTests/CodeReview/**`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - pipeline review engine-side oltre al diff summary
  - `VerifiedFindingsCore` diverso dai test di candidate verification gia' esistenti
  - UI Swift del panel review
- Moduli confinanti da verificare:
  - `CoderIDEMCPServerApp.handleCodeReviewTool`
  - `ReviewCoreBridge`
  - bridge Rust review di candidate verification
- Test da aggiungere o aggiornare:
  - regressione Rust per rename `against_ref` e file untracked nel diff summary
  - regressione Swift per il bridge diff summary
  - regression suite MCP review handler gia' esistente
- Strategia di fix minimo:
  - portare solo il diff summary in Rust senza aprire refactor larghi del resto dell'engine review
  - spostare i quattro file host MCP review come bootstrap host residuo, senza cambiare il contratto tool pubblico
  - mantenere un unico bridge Swift minimale verso il nuovo entrypoint Rust
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml review_diff`
  - `cargo build --manifest-path Native/RustCore/Cargo.toml --lib`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewDiffSummaryServiceTests -only-testing:CoderEngineTests/ReviewCandidateVerificationServiceTests -only-testing:CoderEngineTests/CodeReviewHandlerTests`
  - audit strict review-scope
- Commit previsto: `fix(review): migrate diff summary to rust and drain mcp host`

## Effetto osservato
- review strict prima del batch: `47` legacy non-UI
- review strict dopo il batch: `42` legacy non-UI
- riduzione per prefisso:
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview`: da `4` a `0`
  - `Engine/CoderEngine/Sources/CodeReview`: da `29` a `28`
